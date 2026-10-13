/** Reproducible build without creating dependency/cache directories in the repository. */
import { mkdtemp, cp, rm, mkdir } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const source = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const root = resolve(source, '..');
const workspace = await mkdtemp(join(tmpdir(), 'bic-site-'));
const project = join(workspace, 'web');
async function run(command, args, cwd = project) {
  await new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, stdio: 'inherit', env: process.env });
    child.on('error', reject);
    child.on('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`${command} ${args.join(' ')} failed (${signal || code})`)));
  });
}
try {
  await cp(source, project, { recursive: true, filter: path => !path.split(/[\\/]/).some(p => ['node_modules', '.cache', '.vite'].includes(p)) });
  console.log(`Installing locked frontend dependencies in ${project}`);
  const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  await run(npm, ['ci', '--cache', join(tmpdir(), 'bic-npm-cache'), '--no-audit', '--no-fund']);
  const verifyIndex = process.argv.indexOf('--verify-contracts');
  if (verifyIndex >= 0) {
    const artifacts = process.argv[verifyIndex + 1];
    if (!artifacts) throw new Error('--verify-contracts needs an absolute Foundry output directory.');
    await run(process.execPath, ['scripts/verify-contracts.mjs', resolve(artifacts)]);
  }
  await run(npm, ['run', 'typecheck']);
  await run(npm, ['run', 'build']);
  if (process.argv.includes('--test')) {
    await run(process.execPath, ['scripts/validate.mjs', ...process.argv.slice(2).filter(a => a !== '--test')]);
  }
  // Only the completed production export replaces dist; source and contract files are untouched.
  await mkdir(join(root, 'dist'), { recursive: true });
  await rm(join(root, 'dist'), { recursive: true });
  await cp(join(workspace, 'dist'), join(root, 'dist'), { recursive: true });
  console.log('Production export written to dist/.');
} finally { await rm(workspace, { recursive: true, force: true }); }
