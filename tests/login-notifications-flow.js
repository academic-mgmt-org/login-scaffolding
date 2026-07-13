#!/usr/bin/env node

const {
    openFlow,
    runAction,
    runInterfaceTest,
    studentCredentials,
} = require('./interface-flow-helpers');

runInterfaceTest('LOGIN_CONSULTA_NOTIFICACIONES', studentCredentials(), async ({ page, results, config }) => {
    await openFlow(page, 'usuarios', config);
    await runAction(page, 'usuarios', 'auth_health', { results });
    await runAction(page, 'usuarios', 'auth_ready', { results });
    await runAction(page, 'usuarios', 'auth_live', { results });

    await page.goto(`${config.baseUrl}/notificaciones`, { waitUntil: 'domcontentloaded' });

    if (!(await page.locator('[data-test="notifications-page"]').isVisible())) {
        throw new Error('The notifications interface did not render.');
    }

    const gatewayAlert = page.locator('[data-test="notifications-page"] [role="alert"]');

    if (await gatewayAlert.isVisible()) {
        throw new Error(`Notifications failed: ${(await gatewayAlert.innerText()).trim()}`);
    }

    const unreadCount = Number.parseInt((await page.locator('[data-test="unread-count"]').getAttribute('data-count')) || '-1', 10);

    if (!Number.isInteger(unreadCount) || unreadCount < 0) {
        throw new Error(`Invalid unread notification count: ${unreadCount}.`);
    }

    results.push({ flow: 'notificaciones', action: 'count_list_recent', outcome: 'passed', unreadCount });

    const auditResponsePromise = page.waitForResponse((response) => {
        return response.request().method() === 'POST'
            && new URL(response.url()).pathname === '/notificaciones/auditar-sesion';
    });
    const navigationPromise = page.waitForNavigation({ waitUntil: 'domcontentloaded' });

    await page.locator('[data-test="run-session-audit"]').click();
    const auditResponse = await auditResponsePromise;
    await navigationPromise;

    const audit = page.locator('[data-test="session-audit-result"]');
    const passed = (await audit.getAttribute('data-passed')) === 'true';
    const checks = page.locator('[data-test="session-audit-check"]');

    if (auditResponse.status() !== 200 || !passed || (await checks.count()) !== 6) {
        const summary = await page.locator('[data-test="session-audit-summary"]').innerText().catch(() => 'No audit summary.');
        throw new Error(`Session revocation audit failed: HTTP ${auditResponse.status()}, ${summary}`);
    }

    results.push({ flow: 'auth', action: 'logout_validate_rejections', outcome: 'passed', checks: 6 });
});
