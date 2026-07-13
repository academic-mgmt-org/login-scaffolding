#!/usr/bin/env node

const {
    adminCredentials,
    openFlow,
    prepareStudent,
    requireContext,
    runAction,
    runInterfaceTest,
} = require('./interface-flow-helpers');

runInterfaceTest('MATRICULAS_INSCRIPCION_AJUSTE_CANCELACION', adminCredentials(), async ({ page, results, config }) => {
    await prepareStudent(page, results);
    await openFlow(page, 'matriculas', config);

    for (const action of ['health', 'ready', 'live']) {
        await runAction(page, 'matriculas', action, { results });
    }

    await runAction(page, 'matriculas', 'create_enrollment', { acceptedErrors: [6], results });
    await runAction(page, 'matriculas', 'list_student', { results });
    await requireContext(page, 'enrollment_id');
    await requireContext(page, 'enrollment_code');

    for (const action of ['get_enrollment_id', 'get_enrollment_code', 'list_offer', 'list_auto_subject']) {
        await runAction(page, 'matriculas', action, { results });
    }

    await requireContext(page, 'subject_code');
    await runAction(page, 'matriculas', 'get_auto_subject', { results });
    await runAction(page, 'matriculas', 'create_optional_subject', { results });
    await requireContext(page, 'extra_subject_code');

    for (const action of ['get_optional_subject', 'list_active_subjects', 'list_subject_parallel']) {
        await runAction(page, 'matriculas', action, { results });
    }

    const duplicate = await runAction(page, 'matriculas', 'create_optional_subject', {
        acceptedErrors: [6],
        results,
    });

    if (duplicate.outcome !== 'error' || duplicate.status !== 6) {
        throw new Error('The duplicate subject enrollment was not rejected with AlreadyExists (6).');
    }

    for (const action of [
        'cancel_optional_subject',
        'verify_optional_cancelled',
        'withdraw_enrollment',
        'list_withdrawn',
        'cancel_enrollment',
        'verify_cancelled',
        'audit_subjects',
        'restore_enrollment',
    ]) {
        await runAction(page, 'matriculas', action, { results });
    }

    const missing = await runAction(page, 'matriculas', 'negative_missing', { acceptedErrors: [5], results });

    if (missing.outcome !== 'error' || missing.status !== 5) {
        throw new Error('The missing enrollment was not rejected with NotFound (5).');
    }

    const invalidGrade = await runAction(page, 'matriculas', 'negative_grade', { acceptedErrors: [3], results });

    if (invalidGrade.outcome !== 'error' || invalidGrade.status !== 3) {
        throw new Error('The out-of-range final grade was not rejected with InvalidArgument (3).');
    }
});
