// Bundles the reader page into ../assets/reader/reader.js (one ES module,
// foliate-js's dynamic imports included). PDF support is left out: the
// app opens PDFs with its own viewer.
import { build } from 'esbuild'
import { copyFileSync, mkdirSync } from 'node:fs'

const out = new URL('../assets/reader/', import.meta.url)
mkdirSync(out, { recursive: true })

const noPdf = {
    name: 'no-pdf',
    setup(b) {
        b.onResolve({ filter: /\/pdf\.js$/ }, args => ({ path: args.path, namespace: 'no-pdf' }))
        b.onLoad({ filter: /.*/, namespace: 'no-pdf' }, () => ({
            contents: 'export const makePDF = () => { throw new Error("PDF is opened by the app") }',
        }))
    },
}

await build({
    entryPoints: [new URL('./src/main.js', import.meta.url).pathname],
    bundle: true,
    format: 'esm',
    target: ['chrome90', 'safari15'],
    minify: true,
    legalComments: 'eof',
    outfile: new URL('reader.js', out).pathname,
    plugins: [noPdf],
    logLevel: 'info',
})
copyFileSync(new URL('./src/index.html', import.meta.url), new URL('index.html', out))
