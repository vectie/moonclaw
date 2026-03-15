import { defineConfig } from 'vite'
import rabbita from '@rabbita/vite'

export default defineConfig({
  plugins: [rabbita()],
  server: {
    host: true,
    fs: { allow: ['..', '../..', '../../..'] },
  },
})
