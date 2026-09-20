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

test('X4 the Mac host filters by platform now (C16): platform-only entries exist, live in os blocks, and never carry a base location', () => {
  const foreign = catalog.entries.filter(e => e.platforms && !e.platforms.includes('macos'));
  assert.ok(foreign.length >= 8, `Linux/Windows-only entries (${foreign.length})`);
  assert.ok(foreign.some(e => e.platforms.includes('linux')) && foreign.some(e => e.platforms.includes('windows')), 'both platforms represented');
  for (const e of foreign) {
    assert.ok(pathsOf(e).length === 0 && !COMMANDS.some(k => e[k]), `${e.id}: base fields are macOS — a platform-only entry keeps everything in os.<p>`);
    for (const p of e.platforms) {
      const ov = e.os && e.os[p];
      assert.ok(ov && (pathsOf(ov).length || COMMANDS.some(k => ov[k])), `${e.id}: no location or command for ${p}`);
    }
    assert.ok(!e.children, `${e.id}: children needs a base path; not available to platform-only entries yet`);
  }
  for (const e of catalog.entries.filter(e => !e.platforms || e.platforms.includes('macos'))) {
    assert.ok(pathsOf(e).length || COMMANDS.some(k => e[k]), `${e.id}: a macOS entry needs a base location or command`);
  }
});

test('X5 an entry with a command is portable only where the command is defined for that platform', () => {
  for (const e of catalog.entries) {
    const hasCmd = COMMANDS.some(k => e[k]);
    for (const p of (e.platforms || []).filter(p => p !== 'macos')) {
      if (hasCmd) assert.ok(e.os && e.os[p] && COMMANDS.some(k => e.os[p][k]), `${e.id}: lists ${p} but its shell command has no ${p} version — hide it there or add os.${p}`);
    }
  }
});

test('X7 the first Linux and Windows entries are the expected ones, in existing groups, with sane buckets', () => {
  const groups = new Set(catalog.entries.filter(e => !e.platforms || e.platforms.includes('macos')).map(e => e.group));
  const want = { 'linux-apt-cache': 'safe', 'linux-dnf-cache': 'safe', 'linux-snap-cache': 'safe', 'linux-thumbnails': 'safe', 'linux-journal': 'decide', 'linux-trash': 'safe',
                 'win-temp': 'safe', 'win-update-download': 'safe', 'win-delivery-optimization': 'safe', 'win-crash-dumps': 'safe' };
  for (const [id, bucket] of Object.entries(want)) {
    const e = catalog.entries.find(x => x.id === id);
    assert.ok(e, id); assert.equal(e.bucket, bucket, id);
    assert.ok(groups.has(e.group), `${id}: group "${e.group}" exists on the Mac too (the page renders groups per bucket)`);
    assert.ok(e.note && e.note.length > 20, `${id}: a note explaining it`);
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
