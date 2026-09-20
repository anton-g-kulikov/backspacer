// Platform-awareness invariants over catalog.json and catalog.schema.json (ADR-22, step 1).
// Run: node --test 'Tests/web/*.test.js'
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '../..');
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'catalog.json'), 'utf8'));
const schema = JSON.parse(fs.readFileSync(path.join(root, 'catalog.schema.json'), 'utf8'));
const PLATFORMS = ['macos', 'linux', 'windows'];
const VARS = ['$PROJECTS', '$HOME', '$XDG_CACHE_HOME', '$XDG_CONFIG_HOME', '$XDG_DATA_HOME', '$LOCALAPPDATA', '$APPDATA', '$TEMP'];
const LOCATION = ['path', 'paths', 'glob'];
const COMMANDS = ['sizeCmd', 'infoCmd', 'deleteCmd', 'itemsCmd', 'deleteItemCmd'];
const pathsOf = o => [o.path, ...(o.paths || []), o.glob && o.glob.root].filter(Boolean);
const varsIn = p => (p.match(/\$[A-Z_]+/g) || []);

test('X1 the schema knows platforms and per-OS overrides, both optional', () => {
  const entry = schema.$defs.entry.properties;
  assert.deepEqual(entry.platforms.items.enum, PLATFORMS);
  assert.equal(entry.platforms.minItems, 1);
  assert.ok(!schema.$defs.entry.required.includes('platforms'), 'absent = macOS only');
  const os = entry.os;
  assert.equal(os.additionalProperties, false);
  assert.deepEqual(Object.keys(os.properties).sort(), ['linux', 'windows']);
  for (const p of ['linux', 'windows']) {
    const ov = os.properties[p];
    assert.equal(ov.$ref, '#/$defs/override', p);
  }
  const ov = schema.$defs.override;
  assert.equal(ov.additionalProperties, false);
  for (const k of [...LOCATION, ...COMMANDS]) assert.ok(k in ov.properties, `override carries ${k}`);
});

test('X2 every platforms list and every os key names a known platform', () => {
  for (const e of catalog.entries) {
    if (e.platforms) {
      assert.ok(e.platforms.length >= 1, e.id);
      for (const p of e.platforms) assert.ok(PLATFORMS.includes(p), `${e.id}: platform ${p}`);
      assert.equal(new Set(e.platforms).size, e.platforms.length, `${e.id}: duplicate platform`);
    }
    for (const p of Object.keys(e.os || {})) {
      assert.ok(['linux', 'windows'].includes(p), `${e.id}: os.${p}`);
      assert.ok((e.platforms || []).includes(p), `${e.id}: has os.${p} but does not list ${p} in platforms`);
    }
  }
});

test('X3 path variables come from the allowed set, and platform-specific ones only appear where they mean something', () => {
  const linuxOnly = ['$XDG_CACHE_HOME', '$XDG_CONFIG_HOME', '$XDG_DATA_HOME'];
  const windowsOnly = ['$LOCALAPPDATA', '$APPDATA', '$TEMP'];
  for (const e of catalog.entries) {
    for (const p of pathsOf(e)) for (const v of varsIn(p)) {
      assert.ok(VARS.includes(v), `${e.id}: unknown variable ${v} in ${p}`);
      assert.ok(!windowsOnly.includes(v) && !linuxOnly.includes(v), `${e.id}: ${v} in the base path — base paths are macOS`);
    }
    for (const [os, ov] of Object.entries(e.os || {})) for (const p of pathsOf(ov)) for (const v of varsIn(p)) {
      assert.ok(VARS.includes(v), `${e.id}: unknown variable ${v}`);
      if (os === 'linux') assert.ok(!windowsOnly.includes(v), `${e.id}: ${v} in os.linux`);
      if (os === 'windows') assert.ok(!linuxOnly.includes(v) && !p.startsWith('~'), `${e.id}: ${v || '~'} in os.windows — use $LOCALAPPDATA/$APPDATA/$HOME`);
    }
  }
});

test('X4 until the Mac host filters by platform, every entry still lists macos (nothing foreign can show up in the app)', () => {
  for (const e of catalog.entries) if (e.platforms) assert.ok(e.platforms.includes('macos'), `${e.id}: drops macos before the host filter exists (ADR-22 step 1b)`);
});

test('X5 an entry with a command is portable only where the command is defined for that platform', () => {
  for (const e of catalog.entries) {
    const hasCmd = COMMANDS.some(k => e[k]);
    for (const p of (e.platforms || []).filter(p => p !== 'macos')) {
      if (hasCmd) assert.ok(e.os && e.os[p] && COMMANDS.some(k => e.os[p][k]), `${e.id}: lists ${p} but its shell command has no ${p} version — hide it there or add os.${p}`);
    }
  }
});

test('X6 the portable dot-folder and project entries are marked portable', () => {
  const expected = ['cache-dot', 'regen-gradle', 'regen-cargo', 'regen-m2', 'regen-pub', 'regen-bun', 'cache-rustup', 'proj-node-modules', 'proj-next', 'proj-dotnet', 'ai-claude', 'ai-codex', 'ai-gemini', 'ai-cursor', 'vm-vagrant'];
  for (const id of expected) {
    const e = catalog.entries.find(x => x.id === id);
    assert.ok(e, id);
    assert.ok(e.platforms && e.platforms.includes('linux'), `${id}: should list linux`);
  }
  const portable = catalog.entries.filter(e => e.platforms && e.platforms.length > 1).length;
  assert.ok(portable >= 25, `at least 25 portable entries (${portable})`);
});
