#!/usr/bin/env node

const {
    adminCredentials,
    openFlow,
    prepareStudent,
    requireContext,
    runAction,
    runInterfaceTest,
} = require('./interface-flow-helpers');

runInterfaceTest('SOLICITUDES_BECA_REVISION_RESOLUCION', adminCredentials(), async ({ page, results, config }) => {
    await prepareStudent(page, results);
    await openFlow(page, 'solicitudes', config);

    for (const action of ['health', 'ready', 'live', 'create_request']) {
        await runAction(page, 'solicitudes', action, { results });
    }

    await requireContext(page, 'request_id');
    await requireContext(page, 'request_code');

    for (const action of [
        'get_request_id',
        'get_request_code',
        'list_student',
        'list_received',
        'assign_request',
        'list_assigned',
        'observe_request',
        'add_declaration',
    ]) {
        await runAction(page, 'solicitudes', action, { results });
    }

    await requireContext(page, 'declaration_document_id');
    await runAction(page, 'solicitudes', 'add_bank_document', { results });
    await requireContext(page, 'bank_document_id');

    for (const action of [
        'list_documents',
        'reopen_request',
        'resolve_request',
        'verify_approved',
        'list_approved',
        'create_duplicate',
    ]) {
        await runAction(page, 'solicitudes', action, { results });
    }

    await requireContext(page, 'duplicate_request_id');
    await requireContext(page, 'duplicate_request_code');

    for (const action of ['cancel_duplicate', 'verify_duplicate', 'list_cancelled']) {
        await runAction(page, 'solicitudes', action, { results });
    }
});
