#!/usr/bin/env node

const { chromium } = require('playwright');

const DEFAULT_TIMEOUT_MS = 120_000;

function positiveInteger(value, name, fallback = DEFAULT_TIMEOUT_MS) {
    const parsed = Number.parseInt(value || String(fallback), 10);

    if (!Number.isFinite(parsed) || parsed <= 0) {
        throw new Error(`${name} must be a positive integer.`);
    }

    return parsed;
}

function interfaceConfig() {
    const configuredUrl = process.env.INTERFACE_URL || process.env.LOGIN_URL || 'http://localhost:8000';
    const parsedUrl = new URL(configuredUrl);

    return {
        baseUrl: parsedUrl.origin,
        timeoutMs: positiveInteger(process.env.FLOW_TIMEOUT_MS || process.env.LOGIN_TIMEOUT_MS, 'FLOW_TIMEOUT_MS'),
        headless: process.env.HEADLESS !== 'false',
        channel: process.env.PLAYWRIGHT_CHANNEL || (process.platform === 'win32' ? 'msedge' : undefined),
    };
}

function studentCredentials() {
    return {
        email: process.env.LOGIN_EMAIL || 'allunav@utn.edu.ec',
        password: process.env.LOGIN_PASSWORD || 'password123',
    };
}

function adminCredentials() {
    return {
        email: process.env.ADMIN_EMAIL || 'administrador@demo.com',
        password: process.env.ADMIN_PASSWORD || 'admin123',
    };
}

function teacherCredentials() {
    return {
        email: process.env.TEACHER_EMAIL || 'docente@utn.edu.ec',
        password: process.env.TEACHER_PASSWORD || 'password123',
    };
}

async function launchBrowser(config = interfaceConfig()) {
    const options = { headless: config.headless };

    if (config.channel) {
        options.channel = config.channel;
    }

    return chromium.launch(options);
}

async function authenticatedPage(browser, credentials, config = interfaceConfig()) {
    const context = await browser.newContext();
    const page = await context.newPage();
    page.setDefaultTimeout(config.timeoutMs);
    page.setDefaultNavigationTimeout(config.timeoutMs);

    await page.goto(`${config.baseUrl}/login`, { waitUntil: 'domcontentloaded' });
    await page.locator('input[name="email"]').fill(credentials.email);
    await page.locator('input[name="password"]').fill(credentials.password);

    const [loginResponse] = await Promise.all([
        page.waitForResponse((response) => {
            const request = response.request();
            return request.method() === 'POST' && new URL(response.url()).pathname === '/login';
        }),
        page.locator('[data-test="login-button"]').click(),
    ]);

    await page.waitForURL((url) => url.pathname !== '/login').catch(() => {});
    const finalPath = new URL(page.url()).pathname;

    if (loginResponse.status() >= 400 || finalPath !== '/dashboard') {
        const messages = await page.locator('[role="alert"], [data-flux-error]').allInnerTexts();
        throw new Error(`Login failed for ${credentials.email}: HTTP ${loginResponse.status()}, path ${finalPath}, ${messages.join(' | ')}`);
    }

    return { context, page };
}

async function openFlow(page, flow, config = interfaceConfig()) {
    await page.goto(`${config.baseUrl}/flujos/${flow}`, { waitUntil: 'domcontentloaded' });
    const flowPage = page.locator(`[data-test="flow-page"][data-flow="${flow}"]`);

    if (!(await flowPage.isVisible())) {
        throw new Error(`The ${flow} interface did not render at ${page.url()}.`);
    }
}

async function runAction(page, flow, action, options = {}) {
    const { overrides = {}, acceptedErrors = [], results = [] } = options;

    if (new URL(page.url()).pathname !== `/flujos/${flow}`) {
        await openFlow(page, flow);
    }

    const details = page.locator(`[data-flow-action="${action}"]`);

    if ((await details.count()) !== 1) {
        throw new Error(`Action ${flow}/${action} is missing from the interface.`);
    }

    await details.evaluate((element) => {
        element.open = true;
    });

    const form = details.locator('form[data-test="flow-action-form"]');

    for (const [field, rawValue] of Object.entries(overrides)) {
        const checkbox = form.locator(`input[type="checkbox"][name="payload[${field}]"]`);

        if ((await checkbox.count()) === 1) {
            await checkbox.setChecked(Boolean(rawValue));
            continue;
        }

        const control = form.locator(`input[name="payload[${field}]"], textarea[name="payload[${field}]"]`).last();

        if ((await control.count()) !== 1) {
            throw new Error(`Field ${field} is missing from ${flow}/${action}.`);
        }

        await control.fill(String(rawValue));
    }

    const postPath = `/flujos/${flow}/${action}`;
    const responsePromise = page.waitForResponse((response) => {
        return response.request().method() === 'POST' && new URL(response.url()).pathname === postPath;
    });
    const navigationPromise = page.waitForNavigation({ waitUntil: 'domcontentloaded' });

    await form.locator('button[type="submit"]').click();
    const postResponse = await responsePromise;
    await navigationPromise;

    const error = page.locator('[data-test="flow-error"]');

    if (await error.isVisible()) {
        const status = Number.parseInt((await error.getAttribute('data-status')) || '-1', 10);
        const rpc = (await error.getAttribute('data-rpc')) || 'unknown';
        const detail = (await error.innerText()).trim();
        const result = { flow, action, outcome: 'error', status, rpc, detail };
        results.push(result);

        if (acceptedErrors.includes(status)) {
            return result;
        }

        throw new Error(`${flow}/${action} failed with gRPC ${status} (${rpc}): ${detail}`);
    }

    const success = page.locator('[data-test="flow-success"]');

    if (!(await success.isVisible())) {
        const alerts = await page.locator('[role="alert"], [data-flux-error]').allInnerTexts();
        throw new Error(`${flow}/${action} returned HTTP ${postResponse.status()} without a success result: ${alerts.join(' | ')}`);
    }

    const responseJson = page.locator('[data-test="flow-response-json"]');
    let response = {};

    if (await responseJson.isVisible()) {
        const text = await responseJson.innerText();
        response = text ? JSON.parse(text) : {};
    }

    const result = { flow, action, outcome: 'passed', response };
    results.push(result);

    return result;
}

async function contextValue(page, key) {
    const value = page.locator(`[data-context-key="${key}"]`);
    return (await value.count()) === 1 ? (await value.innerText()).trim() : '';
}

async function requireContext(page, key) {
    const value = await contextValue(page, key);

    if (!value) {
        throw new Error(`The interface did not capture the required context value: ${key}.`);
    }

    return value;
}

async function prepareStudent(page, results = []) {
    await openFlow(page, 'usuarios');
    await runAction(page, 'usuarios', 'create_student', { acceptedErrors: [6], results });
    await runAction(page, 'usuarios', 'get_by_email', { results });
    return requireContext(page, 'student_id');
}

async function prepareEnrollment(page, results = []) {
    await prepareStudent(page, results);
    await openFlow(page, 'matriculas');
    await runAction(page, 'matriculas', 'create_enrollment', { acceptedErrors: [6], results });
    await runAction(page, 'matriculas', 'list_student', { results });
    await requireContext(page, 'enrollment_id');
    await requireContext(page, 'enrollment_code');
    await runAction(page, 'matriculas', 'list_auto_subject', { results });
    await requireContext(page, 'subject_code');
}

async function runInterfaceTest(name, credentials, execute) {
    const config = interfaceConfig();
    const browser = await launchBrowser(config);
    const results = [];
    const startedAt = Date.now();

    try {
        const { context, page } = await authenticatedPage(browser, credentials, config);
        await execute({ browser, context, page, results, config });

        console.log(JSON.stringify({
            success: true,
            flow: name,
            actions: results,
            durationMs: Date.now() - startedAt,
        }, null, 2));
    } catch (error) {
        console.error(JSON.stringify({
            success: false,
            flow: name,
            actions: results,
            error: error.message,
            durationMs: Date.now() - startedAt,
        }, null, 2));
        process.exitCode = 1;
    } finally {
        await browser.close();
    }
}

module.exports = {
    adminCredentials,
    authenticatedPage,
    contextValue,
    interfaceConfig,
    openFlow,
    prepareEnrollment,
    prepareStudent,
    requireContext,
    runAction,
    runInterfaceTest,
    studentCredentials,
    teacherCredentials,
};
