import type { Metadata } from "next";
import { Manrope, Noto_Sans_JP } from "next/font/google";
import Link from "next/link";
import "./globals.css";

const titleFont = Manrope({
  subsets: ["latin", "latin-ext"],
  variable: "--font-title",
  weight: ["500", "600", "700", "800"],
  display: "swap"
});

const bodyFont = Noto_Sans_JP({
  subsets: ["latin"],
  variable: "--font-body",
  display: "swap"
});

export const metadata: Metadata = {
  title: "Lifecast | Build In Public, Back In Public",
  description:
    "Lifecastは、短尺動画で進捗を届けながら支援につなげる、モバイル中心の購入型クラウドファンディングです。"
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ja">
      <body className={`${titleFont.variable} ${bodyFont.variable}`}>
        <header className="header">
          <Link href="/#top" className="logo">
            Lifecast
          </Link>
          <Link href="/#detail" className="waitlistButton">
            Waitlist
          </Link>
        </header>
        {children}
      </body>
    </html>
  );
}
