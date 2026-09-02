// Unit test of the actual inline controller with a minimal, network-free DOM.
// This does not claim to test browser layout, CSP enforcement or downloads UI.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const {script, batch} = JSON.parse(fs.readFileSync(0, "utf8"));

function controller({stored = null, blocked = false} = {}) {
  const elements = new Map();
  const downloads = [];
  const blobs = new Map();
  const storage = new Map();
  class Element {
    constructor() {
      this.children = []; this.events = {}; this.value = "";
      this.textContent = ""; this.disabled = false; this.hidden = false;
      this.classList = {add() {}};
    }
    append(...children) { this.children.push(...children); }
    replaceChildren(...children) { this.children = children; }
    addEventListener(name, callback) { this.events[name] = callback; }
    fire(name) { if (!this.disabled) this.events[name]?.({target: this}); }
    click() {
      if (this.download) downloads.push({name: this.download, blob: blobs.get(this.href)});
      this.fire("click");
    }
    remove() {}
  }
  const localStorage = {
    getItem(key) { return storage.has(key) ? storage.get(key) : stored; },
    setItem(key, value) { storage.set(key, value); },
    removeItem(key) { storage.delete(key); }
  };
  const window = {confirm: () => true};
  Object.defineProperty(window, "localStorage", {get() {
    if (blocked) throw new Error("SecurityError");
    return localStorage;
  }});
  const document = {
    body: new Element(),
    getElementById(id) {
      if (!elements.has(id)) elements.set(id, new Element());
      return elements.get(id);
    },
    createElement: () => new Element()
  };
  vm.runInNewContext(script, {
    document, window, Blob, URL: {
      createObjectURL(blob) { const id = `blob:${blobs.size}`; blobs.set(id, blob); return id; },
      revokeObjectURL() {}
    }, setTimeout() {}
  }, {timeout: 1000});
  const el = id => elements.get(id);
  const alias = value => { el("reviewer").value = value; el("reviewer").fire("change"); };
  const choose = value => {
    const radio = el("decisions").children.map(label => label.children[0]).find(input => input.value === value);
    assert.ok(radio); radio.fire("change");
  };
  function complete() {
    for (let i = 0; i < batch.subject_count; i++) {
      el("subject-nav").children[i].click(); choose("supported_candidate");
    }
  }
  return {el, alias, choose, complete, downloads, storage};
}

(async () => {
  const exported = [];
  for (const blocked of [false, true]) {
    const ui = controller({blocked});
    // Starting a judgment before entering an alias must not discard it.
    ui.choose("supported_candidate"); ui.alias("R1");
    assert.equal(ui.el("progress").value, 1);
    assert.equal(ui.el("conditional").hidden, true);
    ui.complete(); ui.el("export").click();
    assert.equal(ui.downloads.length, 1);
    exported.push(JSON.parse(await ui.downloads[0].blob.text()));
    assert.match(ui.downloads[0].name, /^etiqueta-[0-9a-f]{12}-R1\.json$/);
    ui.alias("R2"); assert.equal(ui.el("progress").value, 0);
    ui.alias("r1"); assert.equal(ui.el("progress").value, batch.subject_count);
    if (blocked) assert.match(ui.el("save-state").textContent, /apenas nesta sessão/);
    ui.el("clear").click(); assert.equal(ui.el("progress").value, 0);
    ui.el("export").click(); assert.equal(ui.downloads.length, 1);
  }
  const target = batch.subjects[0].subject_id;
  const broken = [null, [], "not-an-answer", {},
    {subject_id: target, decision: "rejected_candidate", reason_code: "other", note: 3},
    {subject_id: target, decision: "__proto__", reason_code: "other", note: "x", reviewed_at: "2026-09-01T12:00:00Z"}];
  for (const value of ["null", "[]", "\"text\"", "{invalid", ...broken.map(answer => JSON.stringify({[target]: answer}))]) {
    const ui = controller({stored: value}); ui.alias("R1");
    assert.equal(ui.el("progress").value, 0);
    ui.el("export").click(); assert.equal(ui.downloads.length, 0);
    ui.complete(); ui.el("export").click(); assert.equal(ui.downloads.length, 1);
  }
  const forged = {[target]: {
    subject_id: target, decision: "supported_candidate", reason_code: null,
    note: "", reviewed_at: "2026-09-01T12:00:00Z", injected: "do not export"
  }};
  const sanitized = controller({stored: JSON.stringify(forged)}); sanitized.alias("R1");
  for (let i = 1; i < batch.subject_count; i++) {
    sanitized.el("subject-nav").children[i].click(); sanitized.choose("supported_candidate");
  }
  sanitized.el("export").click();
  const clean = JSON.parse(await sanitized.downloads[0].blob.text());
  assert.equal(Object.hasOwn(clean.decisions[0], "injected"), false);
  exported.push(clean);
  const note = controller(); note.alias("R1"); note.complete();
  note.el("subject-nav").children[0].click(); note.choose("rejected_candidate");
  assert.equal(note.el("conditional").hidden, false);
  note.el("reason").value = "other"; note.el("reason").fire("change");
  note.el("export").click(); assert.equal(note.downloads.length, 0);
  note.el("note").value = "  Algoda\u0303o\nsem\tpercentual\u200b.  "; note.el("note").fire("input");
  note.el("export").click(); assert.equal(note.downloads.length, 1);
  const withNote = JSON.parse(await note.downloads[0].blob.text());
  assert.equal(withNote.decisions[0].note, "Algodão sem percentual.");
  exported.push(withNote);
  process.stdout.write(JSON.stringify({exported}));
})().catch(error => { console.error(error); process.exitCode = 1; });
