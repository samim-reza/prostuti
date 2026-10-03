// Bloom filter persisted as a byte array (pipeline_state.value).
// Lets the news ingester skip already-seen URLs without querying the
// database for every RSS item. False positives (~1%) are re-checked in SQL;
// false negatives are impossible.

export class BloomFilter {
  readonly bits: Uint8Array;
  readonly m: number;
  readonly k: number;

  constructor(m: number, k: number, bits?: Uint8Array) {
    this.m = m;
    this.k = k;
    this.bits = bits ?? new Uint8Array(Math.ceil(m / 8));
  }

  /** Sized for `n` items at false-positive rate `p`. */
  static create(n: number, p = 0.01): BloomFilter {
    const m = Math.ceil((-n * Math.log(p)) / (Math.LN2 * Math.LN2));
    const k = Math.max(1, Math.round((m / n) * Math.LN2));
    return new BloomFilter(m, k);
  }

  private positions(value: string): number[] {
    // Two 32-bit FNV-1a variants combined with Kirsch–Mitzenmacher double hashing.
    let h1 = 0x811c9dc5, h2 = 0x01000193 ^ 0x5bd1e995;
    for (let i = 0; i < value.length; i++) {
      const c = value.charCodeAt(i);
      h1 = Math.imul(h1 ^ c, 0x01000193) >>> 0;
      h2 = Math.imul(h2 ^ c, 0x5bd1e995) >>> 0;
    }
    h2 = (h2 | 1) >>> 0;
    const out: number[] = [];
    for (let i = 0; i < this.k; i++) out.push((h1 + i * h2) % this.m);
    return out;
  }

  add(value: string) {
    for (const p of this.positions(value)) this.bits[p >> 3] |= 1 << (p & 7);
  }

  mightContain(value: string): boolean {
    return this.positions(value).every((p) => (this.bits[p >> 3] & (1 << (p & 7))) !== 0);
  }
}

export const toHex = (b: Uint8Array) => '\\x' + [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
export function fromHex(hex: string): Uint8Array {
  const clean = hex.replace(/^\\x/, '');
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substr(i * 2, 2), 16);
  return out;
}
