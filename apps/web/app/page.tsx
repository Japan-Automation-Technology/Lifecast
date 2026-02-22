const mvpFeatures = [
  {
    title: "Short Video Feed",
    description: "縦型の短尺フィードで、挑戦の進捗をテンポよく発見。"
  },
  {
    title: "3-Tier Plan Setup",
    description: "最大3プランでシンプルに支援募集を開始。"
  },
  {
    title: "All-or-Nothing Funding",
    description: "目標未達時は自動返金される、明快な資金調達モデル。"
  },
  {
    title: "Supporter Identity",
    description: "バッジや支援履歴で、応援が可視化されるコミュニティ。"
  }
];

const flowSteps = [
  "動画で挑戦を投稿",
  "プランを選んで支援",
  "達成までの進捗を一緒に追う"
];

export default function HomePage() {
  return (
    <main className="page">
      <section className="hero">
        <p className="eyebrow">LIFECAST</p>
        <h1>Build In Public, Back In Public.</h1>
        <p className="lead">
          Lifecastは、クリエイターの開発プロセスを短尺動画で届け、
          その場で支援につなげるモバイル中心の購入型クラウドファンディングです。
        </p>
        <div className="heroActions">
          <a href="#features" className="button buttonPrimary">
            MVP機能を見る
          </a>
          <a href="#coming-soon" className="button buttonGhost">
            リリース情報
          </a>
        </div>
      </section>

      <section id="features" className="section">
        <h2>MVPでできること</h2>
        <div className="featureGrid">
          {mvpFeatures.map((feature) => (
            <article key={feature.title} className="featureCard">
              <h3>{feature.title}</h3>
              <p>{feature.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="section">
        <h2>使い方はシンプル</h2>
        <ol className="flowList">
          {flowSteps.map((step) => (
            <li key={step}>{step}</li>
          ))}
        </ol>
      </section>

      <section id="coming-soon" className="section sectionAccent">
        <h2>Web版は準備中</h2>
        <p>
          現在はモバイルアプリ体験を優先して開発中です。Webでは当面、
          サービス紹介とポリシー関連ページを提供予定です。
        </p>
      </section>
    </main>
  );
}
