import typography from "@tailwindcss/typography";

/** @type {import('tailwindcss').Config} */
export default {
  content: ["./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}"],
  theme: {
    extend: {
      colors: {
        eagles: {
          ink: "#06120d",
          night: "#0b1712",
          pine: "#0d3d27",
          green: "#087f45",
          lime: "#9bd33f",
          gold: "#f4c542",
          line: "#dce8df",
          mist: "#f3f8f1",
          white: "#ffffff"
        }
      },
      boxShadow: {
        "match-card": "0 18px 50px rgba(6, 18, 13, 0.16)"
      },
      fontFamily: {
        sans: [
          "Inter",
          "ui-sans-serif",
          "system-ui",
          "-apple-system",
          "BlinkMacSystemFont",
          "Segoe UI",
          "sans-serif"
        ],
        display: [
          "Oswald",
          "Arial Narrow",
          "ui-sans-serif",
          "system-ui",
          "sans-serif"
        ]
      }
    }
  },
  plugins: [typography]
};
