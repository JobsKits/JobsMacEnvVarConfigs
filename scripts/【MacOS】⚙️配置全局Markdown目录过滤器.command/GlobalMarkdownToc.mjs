// Created by Jobs on 2026年10月23日，星期五.
// Register a machine-local converter; repository attributes still select the files.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawnSync } from 'node:child_process';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = HERE;
const DIRECTORY = process.env.JOBS_MARKDOWN_TOC_HOME || path.join(os.homedir(), '.local', 'share', 'jobs-markdown-toc');
const RUNTIME = path.join(DIRECTORY, 'MarkdownToc.mjs');
const STATE = path.join(DIRECTORY, 'installation.json');
const KEYS = ['clean', 'smudge', 'required'].map(name => `filter.jobs-markdown-toc.${name}`);

function git(args, options = {}) {
  return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', ...options });
}

function values(key, global = true) {
  const result = spawnSync('git', ['config', ...(global ? ['--global', '--no-includes'] : []), '--null', '--get-all', key], {
    cwd: ROOT, encoding: 'utf8'
  });
  if (result.status === 1) return [];
  if (result.status !== 0) throw new Error(result.stderr || '无法读取 Git 配置。');
  return result.stdout.split('\0').slice(0, -1);
}

function currentConfiguration() {
  return Object.fromEntries(KEYS.map(key => [key, values(key)]));
}

function replaceConfiguration(configuration) {
  for (const key of KEYS) {
    const result = spawnSync('git', ['config', '--global', '--unset-all', key], { encoding: 'utf8' });
    if (result.status !== 0 && result.status !== 5) throw new Error(result.stderr || `无法更新 ${key}`);
    for (const value of configuration[key]) git(['config', '--global', '--add', key, value]);
  }
}

function same(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function readState() {
  if (!fs.existsSync(STATE)) return null;
  const state = JSON.parse(fs.readFileSync(STATE, 'utf8'));
  if (state.version !== 1 || typeof state.configFile !== 'string' ||
      !['previous', 'installed'].every(field => KEYS.every(key =>
        Array.isArray(state[field]?.[key]) && state[field][key].every(value => typeof value === 'string')))) {
    throw new Error('全局安装记录无效，保留现场。');
  }
  return state;
}

function quote(value) {
  const normalized = value.replaceAll('\\', '/');
  if (/[\r\n]/.test(normalized) || normalized.includes('%')) throw new Error('过滤器路径不能包含换行或百分号。');
  return "'" + normalized.replaceAll("'", "'\\''") + "'";
}

function nodeExecutable() {
  // Prefer the stable Homebrew/PATH link over a versioned Cellar path.
  const candidates = (process.env.PATH || '').split(path.delimiter)
    .filter(Boolean).map(directory => path.resolve(directory, process.platform === 'win32' ? 'node.exe' : 'node'));
  for (const candidate of candidates) {
    try {
      if (fs.realpathSync(candidate) === fs.realpathSync(process.execPath)) return candidate;
    } catch { /* Try the next installed executable. */ }
  }
  return process.execPath;
}

function atomicWrite(file, bytes) {
  const temporary = `${file}.${process.pid}.tmp`;
  try {
    fs.writeFileSync(temporary, bytes, { flag: 'wx', mode: 0o600 });
    fs.renameSync(temporary, file);
  } finally {
    if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
  }
}

function globalConfigFile() {
  if (process.env.GIT_CONFIG_GLOBAL) return path.resolve(process.env.GIT_CONFIG_GLOBAL);
  const traditional = path.join(os.homedir(), '.gitconfig');
  const xdg = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'git', 'config');
  return fs.existsSync(traditional) || !fs.existsSync(xdg) ? traditional : xdg;
}

function assertOwned(state, current) {
  if (!same(current, state.installed) || state.configFile !== globalConfigFile()) {
    throw new Error('全局过滤器或配置文件位置已被其它操作改动，保留现场；先运行 status 核对。');
  }
}

function install() {
  const current = currentConfiguration();
  const state = readState();
  if (state) assertOwned(state, current);
  const existing = spawnSync('git', ['config', '--global', '--includes', '--get-regexp', '^filter\\.jobs-markdown-toc\\.'], {
    cwd: ROOT, encoding: 'utf8'
  });
  if (existing.status !== 0 && existing.status !== 1) throw new Error(existing.stderr || '无法读取全局过滤器。');
  if (!state && existing.status === 0) throw new Error('已有同名全局过滤器但没有本工具安装记录，未覆盖。');
  if (values('filter.jobs-markdown-toc.process', false).length) throw new Error('存在优先级更高的 process 过滤器，未修改。');
  if (!state && fs.existsSync(RUNTIME)) throw new Error(`安装目标已有未登记文件，未覆盖：${RUNTIME}`);

  fs.mkdirSync(DIRECTORY, { recursive: true, mode: 0o700 });
  const canonicalRuntime = path.join(fs.realpathSync(DIRECTORY), 'MarkdownToc.mjs');
  const executable = nodeExecutable();
  const installed = {
    [KEYS[0]]: [`${quote(executable)} ${quote(canonicalRuntime)} clean`],
    [KEYS[1]]: [`${quote(executable)} ${quote(canonicalRuntime)} smudge`],
    [KEYS[2]]: ['true']
  };
  const source = fs.readFileSync(path.join(HERE, 'MarkdownToc.mjs'));
  const previousRuntime = fs.existsSync(RUNTIME) ? fs.readFileSync(RUNTIME) : null;
  const sample = '# Global filter check\n\n[toc]\n\n## 中文与空格\n\n正文\n';
  try {
    if (!previousRuntime?.equals(source)) atomicWrite(RUNTIME, source);
    const generated = execFileSync(executable, [canonicalRuntime, 'clean'], { input: sample, encoding: 'utf8' });
    const restored = execFileSync(executable, [canonicalRuntime, 'smudge'], { input: generated, encoding: 'utf8' });
    if (restored !== sample || !generated.includes('<details>')) throw new Error('机器转换副本往返验证失败。');
    if (!same(installed, current)) replaceConfiguration(installed);
    const next = { version: 1, configFile: globalConfigFile(), previous: state?.previous ?? current, installed };
    if (!same(next, state)) atomicWrite(STATE, JSON.stringify(next, null, 2) + '\n');
  } catch (error) {
    replaceConfiguration(current);
    if (previousRuntime) atomicWrite(RUNTIME, previousRuntime);
    else if (fs.existsSync(RUNTIME)) fs.unlinkSync(RUNTIME);
    throw error;
  }
  console.log(`全局目录过滤器已就绪：${RUNTIME}\n仅处理 .gitattributes 指定 jobs-markdown-toc 的文件；无需逐仓安装。`);
}

function status() {
  for (const key of KEYS) console.log(`${key} = ${values(key).join(' | ') || '(未配置)'}`);
  console.log(`机器转换副本：${fs.existsSync(RUNTIME) ? RUNTIME : '(不存在)'}`);
  const state = readState();
  if (state) assertOwned(state, currentConfiguration());
  if (state?.active === false) console.log('全局配置已撤回；可以重新运行 install 或 setup。');
}

function uninstall() {
  const state = readState();
  if (!state) throw new Error('没有本工具全局安装记录，未修改配置。');
  const current = currentConfiguration();
  assertOwned(state, current);
  try {
    replaceConfiguration(state.previous);
    atomicWrite(STATE, JSON.stringify({ ...state, installed: state.previous, active: false }, null, 2) + '\n');
  } catch (error) {
    replaceConfiguration(current);
    throw error;
  }
  // Keep the converter in case a separately maintained local config uses it.
  console.log('已撤回本工具全局配置；机器副本和工作文件保留，仓内 local 配置不受影响。');
}

function restoreTree() {
  const target = path.resolve(process.argv[3]);
  const root = git(['-C', target, 'rev-parse', '--show-toplevel']).trim();
  if (fs.realpathSync(root) !== fs.realpathSync(target)) throw new Error('请显式指定目标仓库根目录，不自动越界到父仓。');
  const children = git(['-C', root, 'submodule', 'foreach', '--quiet', '--recursive', 'printf "%s\\0" "$toplevel/$sm_path"']).split('\0').filter(Boolean);
  let count = 0;
  for (const repo of [root, ...children]) {
    const tool = path.join(repo, '.jobs-markdown-toc', 'MarkdownToc.mjs');
    if (!fs.existsSync(path.dirname(tool))) continue;
    if (!fs.existsSync(tool) || fs.lstatSync(tool).isSymbolicLink() || fs.lstatSync(path.dirname(tool)).isSymbolicLink()) {
      throw new Error(`恢复工具缺失或为符号链接，停止：${repo}`);
    }
    const run = (args, options = {}) => git(['-C', repo, ...args], options);
    for (const marker of ['MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'sequencer', 'BISECT_START', 'index.lock']) {
      const location = run(['rev-parse', '--git-path', marker]).trim();
      if (fs.existsSync(path.resolve(repo, location))) throw new Error(`存在未完成的 Git 操作：${repo}（${marker}）`);
    }
    if (run(['ls-files', '--unmerged']).trim()) throw new Error(`存在未解决的索引冲突：${repo}`);
    const files = JSON.parse(fs.readFileSync(path.join(repo, '.jobs-markdown-toc', 'manifest.json'), 'utf8')).files;
    if (!Array.isArray(files) || !files.length || files.some(file => typeof file !== 'string' || file.includes('\0'))) {
      throw new Error(`受控文档清单无效：${repo}`);
    }
    const attributes = run(['check-attr', '-z', '--stdin', 'filter'], { input: files.join('\0') + '\0' }).split('\0');
    for (let index = 0; index < files.length; index++) {
      if (attributes[index * 3 + 2] !== 'jobs-markdown-toc') throw new Error(`文档属性未登记或被覆盖：${repo}/${files[index]}`);
    }
    const sample = '# Probe\n\n[toc]\n\n## Heading\n';
    const expected = execFileSync(process.execPath, [fs.realpathSync(RUNTIME), 'clean'], { input: sample });
    const actualOid = run(['hash-object', '--path=.jobs-markdown-toc/README.md', '--stdin'], { input: sample }).trim();
    const expectedOid = run(['hash-object', '--no-filters', '--stdin'], { input: expected }).trim();
    if (actualOid !== expectedOid) throw new Error(`有效 clean 配置或工具说明的属性冲突，未恢复：${repo}`);
    console.log(`恢复：${repo}`);
    for (const mode of ['restore', 'verify']) {
      execFileSync(process.execPath, [fs.realpathSync(tool), mode], { cwd: repo, stdio: 'inherit' });
    }
    count++;
  }
  console.log(`已恢复并验证 ${count} 个仓库；未暂存、提交或推送。`);
}

let lock;
const lockPath = path.join(DIRECTORY, 'installation.lock');
try {
  if (Number(process.versions.node.split('.')[0]) < 20) throw new Error('需要 Node.js 20 或更新版本。');
  if (!path.isAbsolute(DIRECTORY)) throw new Error('JOBS_MARKDOWN_TOC_HOME 必须为绝对目录。');
  if (['GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE'].some(key => process.env[key])) {
    throw new Error('请在没有 Git 目录 / 索引覆盖变量的普通终端运行。');
  }
  const needsRepository = ['setup', 'restore-tree'].includes(process.argv[2]);
  if (process.argv.length !== (needsRepository ? 4 : 3)) {
    throw new Error('install / status / uninstall 不带路径；setup / restore-tree 必须指定一个仓库根目录。');
  }
  if (needsRepository) {
    const target = path.resolve(process.argv[3]);
    const root = git(['-C', target, 'rev-parse', '--show-toplevel']).trim();
    if (fs.realpathSync(target) !== fs.realpathSync(root)) throw new Error('目标不是仓库根目录，未修改全局配置。');
  }
  if (['setup', 'install', 'uninstall', 'restore-tree'].includes(process.argv[2])) {
    fs.mkdirSync(DIRECTORY, { recursive: true, mode: 0o700 });
    lock = fs.openSync(lockPath, 'wx', 0o600);
    fs.writeFileSync(lock, `${process.pid}\n`);
  }
  switch (process.argv[2]) {
    case 'install': install(); break;
    case 'status': status(); break;
    case 'uninstall': uninstall(); break;
    case 'restore-tree': restoreTree(); break;
    case 'setup': install(); restoreTree(); break;
    default: throw new Error('用法：node GlobalMarkdownToc.mjs install | status | uninstall | setup <仓库根目录> | restore-tree <仓库根目录>');
  }
} catch (error) {
  console.error(`全局 Markdown 目录：${error.message}`);
  process.exitCode = 1;
} finally {
  if (lock !== undefined) {
    fs.closeSync(lock);
    fs.unlinkSync(lockPath);
  }
}
