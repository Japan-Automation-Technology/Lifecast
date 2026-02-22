const keyPoints = [
  {
    title: "Short Video Discovery",
    description: "進捗動画を起点に、応援したいプロジェクトをすぐ見つけられる。"
  },
  {
    title: "Simple Support Flow",
    description: "プランを選んでそのまま支援へ。迷わない導線で完了できる。"
  },
  {
    title: "Clear Funding Rule",
    description: "all-or-nothingで明快。目標未達時は自動返金される。"
  }
];

const steps = [
  {
    id: "01",
    title: "見る",
    description: "フィードで進捗動画を見て、気になるプロジェクトを選ぶ。"
  },
  {
    id: "02",
    title: "選ぶ",
    description: "プランの内容・金額・配送見込みを確認して選択する。"
  },
  {
    id: "03",
    title: "支援する",
    description: "チェックアウトを完了し、支援履歴に反映される。"
  }
];

const trustItems = [
  "購入型クラウドファンディング（投資型ではない）",
  "MVPの支援はリターンありのみ",
  "決済成功はサーバー側（Webhook確認）を正とする"
];

export default function HomePage() {
  return (
    <main className="page">
      <header className="header">
        <a href="#top" className="logo">
          Lifecast
        </a>
        <a href="#detail" className="waitlistButton">
          Waitlist
        </a>
      </header>

      <section className="hero" id="top">
        <div className="heroCopy">
          <p className="eyebrow">MOBILE-FIRST CROWDFUNDING</p>
          <h1>Build in public, back in public.</h1>
          <p className="lead">
            短尺動画で進捗を届け、応援につなげる購入型クラウドファンディング。
            発見から支援まで、モバイルでシンプルに完結します。
          </p>
          <a href="#detail" className="primaryButton">
            Waitlistに登録
          </a>
          <p className="heroNote">return-based / all-or-nothing</p>
        </div>

        <div className="heroPoints">
          <h2>Key Points</h2>
          <div className="pointGrid">
            {keyPoints.map((item, index) => (
              <article className="pointCard" key={item.title}>
                <p className="pointIndex">{`0${index + 1}`}</p>
                <h3>{item.title}</h3>
                <p>{item.description}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="detail" id="detail">
        <div className="detailBlock">
          <h2>How It Works</h2>
          <div className="stepList">
            {steps.map((step) => (
              <article className="stepItem" key={step.id}>
                <p className="stepId">{step.id}</p>
                <div>
                  <h3>{step.title}</h3>
                  <p>{step.description}</p>
                </div>
              </article>
            ))}
          </div>
        </div>

        <div className="detailBlock trustBlock">
          <h2>Trust</h2>
          <ul>
            {trustItems.map((item) => (
              <li key={item}>{item}</li>
            ))}
          </ul>
        </div>
      </section>

      <footer className="footer">
        <div>
          <p className="logo">Lifecast</p>
          <p className="footerText">
            Short-video-first purchase-style crowdfunding platform.
          </p>
        </div>
        <div className="footerLinks">
          <a href="#">Policy</a>
          <a href="#">Contact</a>
          <a href="#">Terms</a>
        </div>
      </footer>
    </main>
  );
}
