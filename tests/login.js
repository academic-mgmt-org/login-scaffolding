#!/usr/bin/env node

const { chromium } = require('playwright');

const LOGIN_URL = process.env.LOGIN_URL || 'http://localhost:8000/login';
const EMAIL = process.env.LOGIN_EMAIL || 'allunav@utn.edu.ec';
const PASSWORD = process.env.LOGIN_PASSWORD || 'password123';
const SUCCESS_PATH = process.env.LOGIN_SUCCESS_PATH || '/dashboard';
const TIMEOUT_MS = Number.parseInt(process.env.LOGIN_TIMEOUT_MS || '120000', 10);

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
    if (!Number.isFinite(TIMEOUT_MS) || TIMEOUT_MS <= 0) {
        throw new Error('LOGIN_TIMEOUT_MS must be a positive integer.');
    }

    const launchOptions = {
        headless: process.env.HEADLESS !== 'false',
    };

    if (process.env.PLAYWRIGHT_CHANNEL) {
        launchOptions.channel = process.env.PLAYWRIGHT_CHANNEL;
    } else if (process.platform === 'win32') {
        launchOptions.channel = 'msedge';
    }

    const browser = await chromium.launch(launchOptions);
    const page = await browser.newPage();
    page.setDefaultTimeout(TIMEOUT_MS);
    page.setDefaultNavigationTimeout(TIMEOUT_MS);

    try {
        await page.goto(LOGIN_URL, {
            waitUntil: 'domcontentloaded',
            timeout: TIMEOUT_MS,
        });
        await page.locator('input[name="email"]').fill(EMAIL);
        await page.locator('input[name="password"]').fill(PASSWORD);

        const loginResponsePromise = page.waitForResponse(
            (response) => {
                const request = response.request();
                const url = new URL(response.url());

                return request.method() === 'POST' && url.pathname === '/login';
            },
            { timeout: TIMEOUT_MS },
        );

        await page.locator('[data-test="login-button"]').click();
        const loginResponse = await loginResponsePromise;

        await page.waitForURL((url) => url.pathname !== '/login', {
            timeout: 15_000,
        }).catch(() => {});

        const finalUrl = page.url();
        const finalPath = new URL(finalUrl).pathname;
        const success = loginResponse.status() < 400 && finalPath === SUCCESS_PATH;

        const result = {
            success,
            requestUrl: loginResponse.url(),
            status: loginResponse.status(),
            statusText: loginResponse.statusText(),
            finalUrl,
            response: await visibleLoginResult(page),
        };

        const output = success ? console.log : console.error;
        output('Login result:');
        output(JSON.stringify(result, null, 2));

        if (!success) {
            process.exitCode = 1;
        }
    } catch (error) {
        console.error('Login result:');
        console.error(JSON.stringify({ error: error.message }, null, 2));
        process.exitCode = 1;
    } finally {
        await browser.close();
    }
}

run();
