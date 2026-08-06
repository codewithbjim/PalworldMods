import { resolve } from 'node:path'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

export default defineConfig({
  root: 'src/web',
  base: './',
  resolve: { alias: { '@': resolve('src/web') } },
  plugins: [react(), tailwindcss()],
  build: { outDir: resolve('dist'), emptyOutDir: true }
})
