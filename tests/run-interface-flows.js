#!/usr/bin/env node

const { spawnSync } = require('node:child_process');
const path = require('node:path');

const scripts = [
    'login-notifications-flow.js',
    'user-management-flow.js',
    'enrollment-flow.js',
    'grading-flow.js',
    'academic-request-flow.js',
];

const failures = [];

for (const script of scripts) {
    console.log(`\n=== ${script} ===`);

    const result = spawnSync(process.execPath, [path.join(__dirname, script)], {
        env: process.env,
        stdio: 'inherit',
    });

    if (result.error || result.status !== 0) {
        failures.push({ script, status: result.status, error: result.error?.message });
    }
}

if (failures.length > 0) {
    console.error(`\n${failures.length} interface flow test(s) failed:`);

    for (const failure of failures) {
        console.error(`- ${failure.script}: ${failure.error || `exit ${failure.status}`}`);
    }

    process.exitCode = 1;
} else {
    console.log(`\nAll ${scripts.length} documented interface flows passed.`);
}
