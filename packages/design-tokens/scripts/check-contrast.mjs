#!/usr/bin/env node
/**
 * WCAG 2.2 contrast checker for @assop2b/design-tokens pairs.
 * Run: node scripts/check-contrast.mjs
 */

const TOKENS = {
  '--brand-primary': '#004D77',
  '--brand-secondary': '#5D92AA',
  '--brand-surface': '#002B42',
  '--brand-secondary-text': '#3D6F86',
  '--background': '#FCFCFD',
  '--foreground': '#1C1C26',
  '--card': '#FFFFFF',
  '--card-foreground': '#1C1C26',
  '--primary': '#004D77',
  '--primary-foreground': '#FFFFFF',
  '--secondary': '#E6EEF2',
  '--secondary-foreground': '#004D77',
  '--muted': '#F3F3F6',
  '--muted-foreground': '#5F5F6B',
  '--accent': '#E6EEF2',
  '--accent-foreground': '#004D77',
  '--destructive': '#C42B2B',
  '--destructive-foreground': '#FFFFFF',
  '--border': '#E7E7EC',
  '--sidebar': '#002B42',
  '--sidebar-foreground': '#ECECF0',
  '--sidebar-primary': '#5D92AA',
  '--sidebar-primary-foreground': '#FFFFFF',
  '--sidebar-accent': '#004D77',
  '--sidebar-accent-foreground': '#FFFFFF',
}

const DARK_TOKENS = {
  '--background': '#0D0D11',
  '--foreground': '#ECECF0',
  '--card': '#16161B',
  '--card-foreground': '#ECECF0',
  '--primary': '#5D92AA',
  '--primary-foreground': '#0A1520',
  '--secondary': '#1A2830',
  '--secondary-foreground': '#B8D0DE',
  '--muted': '#1A1A20',
  '--muted-foreground': '#9A9AA6',
  '--accent': '#1A2830',
  '--accent-foreground': '#B8D0DE',
  '--destructive': '#F26D72',
  '--destructive-foreground': '#FFFFFF',
  '--sidebar': '#0A1520',
  '--sidebar-foreground': '#ECECF0',
  '--sidebar-primary': '#5D92AA',
  '--sidebar-primary-foreground': '#FFFFFF',
  '--sidebar-accent': '#004D77',
  '--sidebar-accent-foreground': '#FFFFFF',
}

/** Pairs: [foreground, background, minRatio, label, largeText?] */
const PAIRS = [
  ['--foreground', '--background', 4.5, 'body text'],
  ['--card-foreground', '--card', 4.5, 'card text'],
  ['--primary-foreground', '--primary', 4.5, 'primary button'],
  ['--secondary-foreground', '--secondary', 4.5, 'secondary surface'],
  ['--muted-foreground', '--background', 4.5, 'muted text'],
  ['--accent-foreground', '--accent', 4.5, 'accent surface'],
  ['--destructive', '--background', 4.5, 'error text'],
  ['--destructive-foreground', '--destructive', 4.5, 'destructive button'],
  ['--primary', '--background', 4.5, 'primary link/heading'],
  ['--brand-secondary-text', '--background', 4.5, 'brand secondary text'],
  ['--sidebar-foreground', '--sidebar', 4.5, 'sidebar text'],
  ['--sidebar-primary-foreground', '--sidebar-primary', 3, 'sidebar primary indicator (UI)', true],
  ['--sidebar-accent-foreground', '--sidebar-accent', 4.5, 'sidebar accent'],
  ['--brand-secondary', '--background', 3, 'brand secondary decorative (large only)', true],
  ['--primary-foreground', '--primary', 3, 'primary UI (non-text)', true],
]

const DARK_PAIRS = [
  ['--foreground', '--background', 4.5, 'dark body text'],
  ['--card-foreground', '--card', 4.5, 'dark card text'],
  ['--primary-foreground', '--primary', 4.5, 'dark primary button'],
  ['--secondary-foreground', '--secondary', 4.5, 'dark secondary surface'],
  ['--muted-foreground', '--background', 4.5, 'dark muted text'],
  ['--accent-foreground', '--accent', 4.5, 'dark accent surface'],
  ['--destructive', '--background', 4.5, 'dark error text'],
  ['--sidebar-foreground', '--sidebar', 4.5, 'dark sidebar text'],
  ['--sidebar-primary-foreground', '--sidebar-primary', 3, 'dark sidebar primary indicator (UI)', true],
  ['--sidebar-accent-foreground', '--sidebar-accent', 4.5, 'dark sidebar accent'],
]

function hexToRgb (hex) {
  const n = hex.replace('#', '')
  return [
    Number.parseInt(n.slice(0, 2), 16),
    Number.parseInt(n.slice(2, 4), 16),
    Number.parseInt(n.slice(4, 6), 16),
  ]
}

function relativeLuminance ([r, g, b]) {
  const [rs, gs, bs] = [r, g, b].map((c) => {
    const s = c / 255
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * rs + 0.7152 * gs + 0.0722 * bs
}

function contrastRatio (fg, bg) {
  const l1 = relativeLuminance(hexToRgb(fg))
  const l2 = relativeLuminance(hexToRgb(bg))
  const lighter = Math.max(l1, l2)
  const darker = Math.min(l1, l2)
  return (lighter + 0.05) / (darker + 0.05)
}

function checkPairs (tokens, pairs, mode) {
  let failed = 0
  console.log(`\n=== ${mode} ===`)
  for (const [fgKey, bgKey, min, label, largeOnly] of pairs) {
    const fg = tokens[fgKey]
    const bg = tokens[bgKey]
    if (!fg || !bg) {
      console.error(`  SKIP ${label}: missing token`)
      failed++
      continue
    }
    const ratio = contrastRatio(fg, bg)
    const ok = ratio >= min
    const status = ok ? 'PASS' : 'FAIL'
    const size = largeOnly ? ' (large/UI)' : ''
    console.log(`  ${status} ${label}${size}: ${ratio.toFixed(2)}:1 (min ${min}:1)`)
    if (!ok) failed++
  }
  return failed
}

const lightFails = checkPairs(TOKENS, PAIRS, 'Light mode')
const darkFails = checkPairs(DARK_TOKENS, DARK_PAIRS, 'Dark mode')

if (lightFails + darkFails > 0) {
  console.error(`\n${lightFails + darkFails} contrast check(s) failed.`)
  process.exit(1)
}

console.log('\nAll contrast checks passed.')
