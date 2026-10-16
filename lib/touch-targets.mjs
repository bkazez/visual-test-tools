// The web half of TouchTargets (ios/TouchTargets/TouchTargets.swift): the same
// two rules, read off a page in headless Chrome. Driven by bin/touch-targets.
//
//   1. SIZE. Every target is at least MIN_SIZE (44 px) both ways. A link in
//      running text is exempt: it is sized by the sentence, as WCAG 2.5.8
//      exempts it.
//   2. GAP. Two targets are at least MIN_GAP (16 px) apart, edge to edge, when
//      the distance is a layout decision: both fixed to the viewport (a key
//      above a tab bar), or both in the same scrolling content. A fixed bar is
//      never compared with the page scrolling under it. In a list or table,
//      targets are compared only within one item or row, because rows abut by
//      design; so do the items of one tab bar or menu bar (nav, tablist,
//      menubar, toolbar), which iOS exempts as Apple's own.
//   A form label is not a target of its own: it is part of its field's.
//   Overlapping targets fail at any size; a target inside another is not a
//   pair. A target covered by something else at its centre is skipped.

export function findProblems({ minSize, minGap }) {
  const SELECTOR = [
    'a[href]', 'button', 'input:not([type=hidden])', 'select', 'textarea', 'summary',
    '[role=button]', '[role=link]', '[role=tab]', '[role=menuitem]', '[role=checkbox]',
    '[role=switch]', '[onclick]', '[tabindex]:not([tabindex="-1"])',
  ].join(',');
  const view = { w: innerWidth, h: innerHeight };

  const visible = (el, r) => {
    if (r.width === 0 || r.height === 0) return false;
    if (r.bottom <= 0 || r.right <= 0 || r.top >= view.h || r.left >= view.w) return false;
    const s = getComputedStyle(el);
    return s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0;
  };
  const hittable = (el, r) => {
    const x = Math.min(Math.max(r.left + r.width / 2, 0), view.w - 1);
    const y = Math.min(Math.max(r.top + r.height / 2, 0), view.h - 1);
    const hit = document.elementFromPoint(x, y);
    return !!hit && (hit === el || el.contains(hit) || hit.contains(el));
  };
  const fixedRoot = (el) => {
    for (let n = el; n && n !== document.body; n = n.parentElement) {
      const p = getComputedStyle(n).position;
      if (p === 'fixed' || p === 'sticky') return n;
    }
    return null;
  };
  const scroller = (el) => {
    for (let n = el.parentElement; n && n !== document.body; n = n.parentElement) {
      const s = getComputedStyle(n);
      if (/(auto|scroll)/.test(s.overflow + s.overflowX + s.overflowY)) return n;
    }
    return null;
  };
  const inRunningText = (el) =>
    el.tagName === 'A' && getComputedStyle(el).display === 'inline' && !!el.closest('p, li > p, blockquote');
  const name = (el) => {
    const words = (el.getAttribute('aria-label') || el.innerText || el.value || el.getAttribute('placeholder')
      || el.getAttribute('title') || el.tagName.toLowerCase()).trim().replace(/\s+/g, ' ').slice(0, 40);
    return `"${words}" (${el.tagName.toLowerCase()})`;
  };

  const targets = [...document.querySelectorAll(SELECTOR)]
    .map(el => ({ el, r: el.getBoundingClientRect() }))
    .filter(({ el, r }) => visible(el, r))
    .map(({ el, r }) => ({
      el, r, name: name(el),
      fixed: fixedRoot(el), scroll: scroller(el),
      item: el.closest('li, tr, [role=row], [role=listitem], [role=option]'),
      bar: el.closest('nav, [role=tablist], [role=menubar], [role=toolbar]'),
      inline: inRunningText(el),
    }));

  const problems = [];
  for (const t of targets) {
    if (t.inline) continue;
    const short = Math.min(t.r.width, t.r.height);
    if (short < minSize - 0.5 && hittable(t.el, t.r)) {
      problems.push({ severity: minSize - short,
        text: `${t.name} is ${Math.round(t.r.width)}×${Math.round(t.r.height)} px; the minimum is ${minSize} px` });
    }
  }
  const comparable = (a, b) => {
    if (a.el.contains(b.el) || b.el.contains(a.el)) return false;
    if (a.bar && a.bar === b.bar) return false;
    if (!!a.fixed !== !!b.fixed) return false;
    if (a.fixed) return true;
    if (a.scroll !== b.scroll) return false;
    const aItem = a.bar ? null : a.item, bItem = b.bar ? null : b.item;
    if ((aItem || bItem) && aItem !== bItem) return false;
    return true;
  };
  const distance = (a, b) => {
    const ix = Math.min(a.right, b.right) - Math.max(a.left, b.left);
    const iy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
    if (ix > 0 && iy > 0) return -Math.min(ix, iy);
    const dx = Math.max(0, b.left - a.right, a.left - b.right);
    const dy = Math.max(0, b.top - a.bottom, a.top - b.bottom);
    return Math.hypot(dx, dy);
  };
  for (let i = 0; i < targets.length; i++) {
    for (let j = i + 1; j < targets.length; j++) {
      const a = targets[i], b = targets[j];
      if (a.inline && b.inline) continue;
      if (!comparable(a, b)) continue;
      const gap = distance(a.r, b.r);
      if (gap < minGap - 0.5 && hittable(a.el, a.r) && hittable(b.el, b.r)) {
        problems.push({ severity: minGap - gap, text: gap < 0
          ? `${a.name} and ${b.name} overlap`
          : `${a.name} and ${b.name} are ${Math.round(gap)} px apart; the minimum is ${minGap} px` });
      }
    }
  }
  return problems.sort((a, b) => b.severity - a.severity).map(p => p.text);
}
