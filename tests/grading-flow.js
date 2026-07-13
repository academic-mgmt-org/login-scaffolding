#!/usr/bin/env node

const {
    adminCredentials,
    openFlow,
    prepareEnrollment,
    requireContext,
    runAction,
    runInterfaceTest,
} = require('./interface-flow-helpers');

runInterfaceTest('CALIFICACIONES_REGISTRO_PUBLICACION_NOTAS', adminCredentials(), async ({ page, results, config }) => {
    await prepareEnrollment(page, results);
    await openFlow(page, 'calificaciones', config);

    for (const action of ['health', 'ready', 'live', 'create_exam', 'create_project']) {
        await runAction(page, 'calificaciones', action, { results });
    }

    await requireContext(page, 'exam_component_id');
    await requireContext(page, 'project_component_id');

    for (const action of ['list_components', 'update_project', 'find_subject']) {
        await runAction(page, 'calificaciones', action, { results });
    }

    // The documented flow allows creating the grading-side subject when the
    // enrollment synchronization did not create it. AlreadyExists proves the
    // synchronized record is present and is therefore an accepted branch.
    await runAction(page, 'calificaciones', 'create_subject', { acceptedErrors: [6], results });
    await runAction(page, 'calificaciones', 'list_subjects', { results });

    for (const action of ['register_exam', 'register_project']) {
        await runAction(page, 'calificaciones', action, { results });
    }

    await requireContext(page, 'exam_grade_id');
    await requireContext(page, 'project_grade_id');

    for (const action of [
        'get_exam',
        'list_subject_grades',
        'list_student_grades',
        'update_exam',
        'list_published',
        'publish',
        'final_grade',
        'cycle_summary',
        'disable_project',
        'verify_component',
        'verify_grades',
    ]) {
        await runAction(page, 'calificaciones', action, { results });
    }
});
