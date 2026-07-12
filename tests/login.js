#!/usr/bin/env node

const { chromium } = require('playwright');

const LOGIN_URL = process.env.LOGIN_URL || 'http://localhost/login';
const EMAIL = 'allunav@utn.edu.ec';
const PASSWORD = 'password123';

async function visibleLoginResult(page) {
    const messages = await page
        .locator('[role="alert"], [data-flux-error]')
        .allInnerTexts();
    const nonEmptyMessages = [...new Set(messages.map((message) => message.trim()).filter(Boolean))];

    if (nonEmptyMessages.length > 0) {
        return nonEmptyMessages.join('\n');
    }

    // A successful login may not render an alert, so return the visible page
    // contents to make the outcome observable in every case.
    return (await page.locator('body').innerText()).trim();
}

async function run() {
    const launchOptions = {
        headless: process.env.HEADLESS !== 'false',
    };

    if (process.env.PLAYWRIGHT_CHANNEL) {
        launchOptions.channel = process.env.PLAYWRIGHT_CHANNEL;
    }

    const browser = await chromium.launch(launchOptions);
    const page = await browser.newPage();

    try {
        await page.goto(LOGIN_URL, { waitUntil: 'domcontentloaded' });
        await page.locator('input[name="email"]').fill(EMAIL);
        await page.locator('input[name="password"]').fill(PASSWORD);

        const loginResponsePromise = page.waitForResponse((response) => {
            const request = response.request();
            const url = new URL(response.url());

            return request.method() === 'POST' && url.pathname === '/login';
        });

        await page.locator('[data-test="login-button"]').click();
        const loginResponse = await loginResponsePromise;

        const result = {
            requestUrl: loginResponse.url(),
            status: loginResponse.status(),
            statusText: loginResponse.statusText(),
            finalUrl: page.url(),
            response: await visibleLoginResult(page),
        };

        console.log('Login result:');
        console.log(JSON.stringify(result, null, 2));
    } catch (error) {
        console.error('Login result:');
        console.error(JSON.stringify({ error: error.message }, null, 2));
        process.exitCode = 1;
    } finally {
        await browser.close();
    }
}

run();
