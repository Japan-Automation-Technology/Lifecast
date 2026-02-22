import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Lifecast | Build In Public, Back In Public",
  description:
    "Lifecastは、短尺動画で進捗を届けながら支援を集める、購入型クラウドファンディングプラットフォームです。"
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ja">
      <body>{children}</body>
    </html>
  );
}
