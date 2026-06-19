#!/usr/bin/env python3
import argparse
import asyncio
import sys
from pathlib import Path

from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError


COMPOSER_SELECTORS = [
    '[data-testid="composer"] div[contenteditable="true"]',
    'div[contenteditable="true"][role="textbox"]',
    'textarea[data-testid="prompt-textarea"]',
    'textarea',
]


async def find_composer(page):
    for selector in COMPOSER_SELECTORS:
        locator = page.locator(selector).last
        try:
            await locator.wait_for(state="visible", timeout=5000)
            return locator
        except PlaywrightTimeoutError:
            continue
    return None


async def set_prompt(locator, prompt):
    try:
        await locator.fill(prompt, timeout=10000)
        return
    except Exception:
        pass

    await locator.click()
    await locator.evaluate(
        """(node, value) => {
            node.focus();
            if (node.tagName && node.tagName.toLowerCase() === 'textarea') {
                node.value = value;
            } else {
                node.innerText = value;
            }
            node.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText', data: value}));
        }""",
        prompt,
    )


async def main():
    parser = argparse.ArgumentParser(description="Open a ChatGPT conversation in Edge and insert a review prompt.")
    parser.add_argument("--chat-url", required=True)
    parser.add_argument("--prompt-file", required=True)
    parser.add_argument("--cdp-url", default="http://127.0.0.1:9222")
    parser.add_argument("--send", action="store_true")
    args = parser.parse_args()

    prompt_path = Path(args.prompt_file)
    prompt = prompt_path.read_text(encoding="utf-8")

    async with async_playwright() as p:
        try:
            browser = await p.chromium.connect_over_cdp(args.cdp_url)
        except Exception as exc:
            print(f"Unable to connect to Edge CDP at {args.cdp_url}: {exc}", file=sys.stderr)
            return 2

        context = browser.contexts[0] if browser.contexts else await browser.new_context()
        page = await context.new_page()
        await page.goto(args.chat_url, wait_until="domcontentloaded", timeout=60000)

        composer = await find_composer(page)
        if composer is None:
            print("ChatGPT composer was not found. Paste the prompt manually from:", prompt_path, file=sys.stderr)
            return 3

        await set_prompt(composer, prompt)

        if args.send:
            await composer.press("Enter")

        print(f"Prompt {'sent' if args.send else 'inserted'} in ChatGPT: {args.chat_url}")
        return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
