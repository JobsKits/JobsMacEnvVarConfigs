// Created by Jobs on 2026年10月23日，星期五.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { cleanMarkdown, smudgeMarkdown } from './MarkdownToc.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SOURCE = '# 示例\n\n[toc]\n\n## 一、中文\n\n正文\n';

function fixture(t) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'global-toc-'));
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  const env = {
    ...process.env,
    GIT_CONFIG_GLOBAL: path.join(temporary, 'global.gitconfig'),
    GIT_CONFIG_NOSYSTEM: '1',
    GIT_CONFIG_COUNT: '0',
    GIT_TERMINAL_PROMPT: '0',
    JOBS_MARKDOWN_TOC_HOME: path.join(temporary, "machine tools's 中文")
  };
  for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE']) delete env[key];
  function run(program, args, cwd = temporary, success = true) {
    const result = spawnSync(program, args, { cwd, env, encoding: 'utf8' });
    if (success) assert.equal(result.status, 0, `${program} ${args.join(' ')}\n${result.stderr}\n${result.stdout}`);
    return result;
  }
  const git = (repo, ...args) => run('git', args, repo).stdout;
  function repo(name) {
    const directory = path.join(temporary, name);
    fs.mkdirSync(path.join(directory, '.jobs-markdown-toc'), { recursive: true });
    for (const name of ['MarkdownToc.mjs', 'GlobalMarkdownToc.mjs']) {
      fs.copyFileSync(path.join(HERE, name), path.join(directory, '.jobs-markdown-toc', name));
    }
    fs.writeFileSync(path.join(directory, '.jobs-markdown-toc/manifest.json'), JSON.stringify({ version: 1, files: ['README.md', '.jobs-markdown-toc/README.md'] }));
    fs.writeFileSync(path.join(directory, '.gitattributes'), 'README.md filter=jobs-markdown-toc\n.jobs-markdown-toc/README.md filter=jobs-markdown-toc\n');
    for (const file of ['README.md', '.jobs-markdown-toc/README.md']) fs.writeFileSync(path.join(directory, file), cleanMarkdown(SOURCE));
    fs.writeFileSync(path.join(directory, 'plain.md'), SOURCE);
    git(directory, 'init', '-q');
    git(directory, 'add', '.');
    git(directory, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture');
    return directory;
  }
  const source = repo('repo 中文 space');
  const command = (mode, directory = source, success = true) => run(process.execPath, [path.join(directory, '.jobs-markdown-toc/GlobalMarkdownToc.mjs'), mode, ...(['setup', 'restore-tree'].includes(mode) ? [directory] : [])], directory, success);
  return { temporary, env, run, git, repo, source, command };
}

test('global driver handles first checkout and add after source moves; unregistered files stay untouched', t => {
  const f = fixture(t);
  f.git(f.source, 'config', '--global', 'user.name', 'Preserved user');
  f.command('install');
  const moved = path.join(f.temporary, 'moved installer');
  fs.renameSync(f.source, moved);
  // A newly cloned repository's converter must never be the global executable.
  fs.writeFileSync(path.join(moved, '.jobs-markdown-toc/MarkdownToc.mjs'), 'throw new Error("repository converter must not execute during checkout");\n');
  f.git(moved, 'add', '.jobs-markdown-toc/MarkdownToc.mjs');
  f.git(moved, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'repository converter sentinel');
  const clone = path.join(f.temporary, 'fresh clone');
  f.git(moved, 'clone', '--quiet', '--no-local', moved, clone);
  assert.equal(fs.readFileSync(path.join(clone, 'README.md'), 'utf8'), SOURCE);
  assert.equal(fs.readFileSync(path.join(clone, 'plain.md'), 'utf8'), SOURCE);
  assert.equal(f.git(clone, 'show', 'HEAD:README.md'), cleanMarkdown(SOURCE));
  assert.equal(f.git(clone, 'status', '--porcelain'), '');
  const edited = SOURCE + '\n### 二级目录\n';
  fs.writeFileSync(path.join(clone, 'README.md'), edited);
  f.git(clone, 'add', 'README.md');
  assert.equal(f.git(clone, 'show', ':README.md'), cleanMarkdown(edited));
  assert.equal(fs.readFileSync(path.join(clone, 'README.md'), 'utf8'), edited);
  assert.equal(f.git(clone, 'config', '--global', '--get', 'user.name').trim(), 'Preserved user');
});

test('setup restores existing root and submodule edits without replacing staged blobs or flags', t => {
  const f = fixture(t);
  const childSource = f.repo('child-source');
  f.git(f.source, '-c', 'protocol.file.allow=always', 'submodule', 'add', '--quiet', childSource, '子模块');
  const child = path.join(f.source, '子模块');
  const roots = [f.source, child];
  const before = roots.map(repo => {
    const generated = cleanMarkdown(SOURCE + '\n未暂存的正文\n');
    fs.writeFileSync(path.join(repo, 'README.md'), generated);
    f.git(repo, 'update-index', '--assume-unchanged', '.jobs-markdown-toc/README.md');
    return { staged: f.git(repo, 'ls-files', '--stage', '-z'), flags: f.git(repo, 'ls-files', '-v', '-z'), local: smudgeMarkdown(generated) };
  });
  f.command('setup');
  roots.forEach((repo, index) => {
    assert.equal(fs.readFileSync(path.join(repo, 'README.md'), 'utf8'), before[index].local);
    assert.equal(f.git(repo, 'ls-files', '--stage', '-z'), before[index].staged);
    assert.equal(f.git(repo, 'ls-files', '-v', '-z'), before[index].flags);
  });
});

test('repeat install is idempotent; uninstall and reinstall preserve unrelated settings', t => {
  const f = fixture(t);
  f.git(f.source, 'config', '--global', 'alias.example', 'status --short');
  f.command('install');
  const original = fs.readFileSync(f.env.GIT_CONFIG_GLOBAL, 'utf8');
  f.command('install');
  assert.equal(fs.readFileSync(f.env.GIT_CONFIG_GLOBAL, 'utf8'), original);
  f.command('uninstall');
  assert.equal(f.git(f.source, 'config', '--global', '--get', 'alias.example').trim(), 'status --short');
  assert.equal(f.run('git', ['config', '--get', 'filter.jobs-markdown-toc.clean'], f.source, false).status, 1);
  f.command('install');
  assert.equal(fs.readFileSync(f.env.GIT_CONFIG_GLOBAL, 'utf8'), original);
});

test('foreign configuration and later edits are not overwritten', t => {
  const f = fixture(t);
  f.git(f.source, 'config', '--global', 'filter.jobs-markdown-toc.clean', 'cat');
  assert.notEqual(f.command('install', f.source, false).status, 0);
  assert.equal(f.git(f.source, 'config', '--global', '--get', 'filter.jobs-markdown-toc.clean').trim(), 'cat');
  f.git(f.source, 'config', '--global', '--unset', 'filter.jobs-markdown-toc.clean');
  f.command('install');
  f.git(f.source, 'config', '--global', 'filter.jobs-markdown-toc.clean', 'cat');
  assert.notEqual(f.command('uninstall', f.source, false).status, 0);
  assert.equal(f.git(f.source, 'config', '--global', '--get', 'filter.jobs-markdown-toc.clean').trim(), 'cat');
});

test('restore detects a conflicting local driver before changing documents', t => {
  const f = fixture(t);
  f.command('install');
  f.git(f.source, 'config', '--local', 'filter.jobs-markdown-toc.clean', 'cat');
  assert.notEqual(f.command('restore-tree', f.source, false).status, 0);
  assert.equal(fs.readFileSync(path.join(f.source, 'README.md'), 'utf8'), cleanMarkdown(SOURCE));
});

test('copied command bundle works without the source repo and restores only an explicit target', t => {
  const f = fixture(t);
  const name = '【MacOS】⚙️配置全局Markdown目录过滤器.command';
  const bundle = path.join(f.temporary, 'deployed Scripts', name);
  fs.mkdirSync(bundle, { recursive: true });
  for (const file of [name, 'GlobalMarkdownToc.mjs', 'MarkdownToc.mjs']) {
    fs.copyFileSync(path.join(HERE, file), path.join(bundle, file));
  }
  const head = f.git(f.source, 'rev-parse', 'HEAD');
  f.run('/bin/zsh', [path.join(bundle, name)]);
  assert.equal(fs.readFileSync(path.join(f.source, 'README.md'), 'utf8'), cleanMarkdown(SOURCE));
  f.run('/bin/zsh', [path.join(bundle, name), 'setup', f.source]);
  assert.equal(fs.readFileSync(path.join(f.source, 'README.md'), 'utf8'), SOURCE);
  assert.equal(f.git(f.source, 'rev-parse', 'HEAD'), head);
});

test('setup rejects a missing or non-root target before writing global configuration', t => {
  const f = fixture(t);
  const helper = path.join(f.source, '.jobs-markdown-toc/GlobalMarkdownToc.mjs');
  assert.notEqual(f.run(process.execPath, [helper, 'setup'], f.source, false).status, 0);
  assert.notEqual(f.run(process.execPath, [helper, 'setup', path.join(f.source, '.jobs-markdown-toc')], f.source, false).status, 0);
  assert.equal(fs.existsSync(f.env.GIT_CONFIG_GLOBAL), false);
});
