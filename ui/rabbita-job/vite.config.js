import { defineConfig } from 'vite'
import rabbita from '@rabbita/vite'

export default defineConfig({
  plugins: [rabbita()],
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules')) {
            if (id.includes('@rabbita')) return 'rabbita-vendor'
            return 'vendor'
          }
        },
      },
    },
  },
  server: {
    host: true,
    fs: { allow: ['..', '../..', '../../..'] },
  },
})
