#!/usr/bin/env node
/**
 * Skill Eval Optimizer - 高清截图脚本
 *
 * 用法: node scripts/screenshot.mjs [html文件路径] [输出png路径]
 *
 * 特性:
 * - 2x deviceScaleFactor，输出高清图
 * - 只截 .card 元素，无多余背景
 * - 等待字体加载完成
 * - 截完自动用 open 命令打开图片（macOS；其他平台跳过）
 *
 * Playwright 解析顺序：
 * 1. 环境变量 PLAYWRIGHT_PATH（指向 playwright-core 或 playwright 包根目录）
 * 2. 本 skill 目录下 node_modules/playwright-core 或 playwright
 * 3. 向上查找 node_modules（与 monorepo 共存）
 */

import {createRequire} from 'module';
import {fileURLToPath} from 'url';
import path from 'path';
import fs from 'fs';
import {execSync} from 'child_process';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const skillRoot = path.resolve(__dirname, '..');

function resolvePlaywright() {
  const custom = process.env.PLAYWRIGHT_PATH;
  if (custom) {
    const p = path.resolve(custom);
    if (fs.existsSync(p)) {
      try {
        return require(path.join(p, 'index.js'));
      } catch {
        try {
          return require(p);
        } catch {
          /* fall through */
        }
      }
    }
  }

  const candidates = [
    path.join(skillRoot, 'node_modules', 'playwright-core'),
    path.join(skillRoot, 'node_modules', 'playwright'),
  ];

  let dir = skillRoot;
  for (let i = 0; i < 6; i++) {
    candidates.push(
      path.join(dir, 'node_modules', 'playwright-core'),
      path.join(dir, 'node_modules', 'playwright'),
    );
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }

  for (const base of candidates) {
    if (!fs.existsSync(base)) continue;
    try {
      return require(path.join(base, 'index.js'));
    } catch {
      try {
        return require(base);
      } catch {
        /* next */
      }
    }
  }

  console.error(
    '未找到 playwright/playwright-core。请任选其一：\n' +
      '  - 在 skill 目录执行: npm install playwright-core && npx playwright install chromium\n' +
      '  - 或设置 PLAYWRIGHT_PATH 指向已安装的 playwright-core 包目录',
  );
  process.exit(2);
}

const pw = resolvePlaywright();

const htmlPath =
  process.argv[2] || path.join(skillRoot, 'templates', 'result-card.html');
const outputPath =
  process.argv[3] || path.join(skillRoot, 'templates', 'result-card.png');

async function screenshot() {
  const browser = await pw.chromium.launch();

  try {
    const context = await browser.newContext({
      viewport: {width: 920, height: 1600},
      deviceScaleFactor: 2,
    });
    const page = await context.newPage();

    const fileUrl = htmlPath.startsWith('file:')
      ? htmlPath
      : `file://${path.resolve(htmlPath)}`;
    await page.goto(fileUrl, {waitUntil: 'networkidle'});

    await page.evaluate(() => document.fonts.ready);
    await new Promise((r) => setTimeout(r, 2000));

    const card = await page.locator('.card');
    await card.screenshot({
      path: outputPath,
      type: 'png',
    });

    console.log(`截图完成: ${outputPath}`);

    const box = await card.boundingBox();
    if (box) {
      console.log(
        `卡片尺寸: ${Math.round(box.width)}x${Math.round(box.height)}px (CSS)`,
      );
      console.log(
        `输出尺寸: ${Math.round(box.width * 2)}x${Math.round(box.height * 2)}px (2x高清)`,
      );
    }
  } finally {
    await browser.close();
  }

  if (process.platform === 'darwin') {
    try {
      execSync(`open "${outputPath}"`, {stdio: 'ignore'});
    } catch {
      /* ignore */
    }
  }
}

screenshot().catch((err) => {
  console.error('截图失败:', err.message);
  process.exit(1);
});
