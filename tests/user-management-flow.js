#!/usr/bin/env node

const {
    adminCredentials,
    authenticatedPage,
    openFlow,
    requireContext,
    runAction,
    runInterfaceTest,
    studentCredentials,
    teacherCredentials,
} = require('./interface-flow-helpers');

async function expectRoleDenied(browser, credentials, suffix, results, config) {
    const { context, page } = await authenticatedPage(browser, credentials, config);

    try {
        await openFlow(page, 'usuarios', config);
        const result = await runAction(page, 'usuarios', 'create_student', {
            acceptedErrors: [7],
            overrides: {
                email: `intento.${suffix}.${Date.now()}@utn.edu.ec`,
                identificacion: `19${String(Date.now()).slice(-8)}`,
            },
            results,
        });

        if (result.outcome !== 'error' || result.status !== 7) {
            throw new Error(`The ${suffix} role was not rejected with PermissionDenied (7).`);
        }
    } finally {
        await context.close();
    }
}

runInterfaceTest('GESTION_USUARIOS_ALTA_ESTUDIANTE', adminCredentials(), async ({ browser, page, results, config }) => {
    await openFlow(page, 'usuarios', config);

    for (const action of ['auth_health', 'auth_ready', 'auth_live', 'health', 'ready', 'live']) {
        await runAction(page, 'usuarios', action, { results });
    }

    for (const action of ['list_roles', 'list_faculties', 'list_careers']) {
        await runAction(page, 'usuarios', action, { results });
    }

    await runAction(page, 'usuarios', 'create_student', { acceptedErrors: [6], results });
    await runAction(page, 'usuarios', 'get_by_email', { results });
    await requireContext(page, 'student_id');

    for (const action of [
        'get_by_document',
        'search_career',
        'search_faculty',
        'search_text',
        'update_contact',
        'block_student',
        'disable_student',
        'verify_inactive',
        'activate_student',
        'verify_active',
        'seed_user',
    ]) {
        await runAction(page, 'usuarios', action, { results });
    }

    const duplicate = await runAction(page, 'usuarios', 'create_student', { acceptedErrors: [6], results });

    if (duplicate.outcome !== 'error' || duplicate.status !== 6) {
        throw new Error('The duplicate student was not rejected with AlreadyExists (6).');
    }

    const anonymous = await runAction(page, 'usuarios', 'negative_no_login', { acceptedErrors: [16], results });

    if (anonymous.outcome !== 'error' || anonymous.status !== 16) {
        throw new Error('ListRoles without authorization was not rejected with Unauthenticated (16).');
    }

    const missing = await runAction(page, 'usuarios', 'negative_missing', { acceptedErrors: [5], results });

    if (missing.outcome !== 'error' || missing.status !== 5) {
        throw new Error('The missing user was not rejected with NotFound (5).');
    }

    await expectRoleDenied(browser, studentCredentials(), 'estudiante', results, config);
    await expectRoleDenied(browser, teacherCredentials(), 'docente', results, config);
});
