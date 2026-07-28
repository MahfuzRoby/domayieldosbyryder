import type { Metadata, Viewport } from "next"
import { Geist, Geist_Mono } from "next/font/google"
import "./globals.css"

const geistSans = Geist({ subsets: ["latin"], variable: "--font-geist-sans" })
const geistMono = Geist_Mono({ subsets: ["latin"], variable: "--font-geist-mono" })

export const metadata: Metadata = {
  title: "Domayield — Domain-Collateralized Lending on Doma",
  description:
    "Deposit USDC.e to earn yield, or borrow against tokenized Doma domains. A DeFi lending protocol built on the Doma chain.",
  generator: "v0.app",
}

export const viewport: Viewport = {
  themeColor: "#070a12",
  colorScheme: "dark",
}

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable} bg-background`}>
      <body className="font-sans antialiased bg-background text-foreground">{children}</body>
    </html>
  )
}
