import Image from "next/image";

const keyPoints = [
  {
    title: "Short Video Discovery",
    description: "進捗動画を起点に、応援したいプロジェクトをすぐ見つけられる。",
  },
  {
    title: "Participatory Support",
    description: "プロセスを応援しながら、プロジェクトの一員として参加できる。",
  },
  {
    title: "Simple Support Flow",
    description: "プランを選んでそのまま支援へ。迷わない導線で完了できる。",
  },
];

const steps = [
  {
    id: "01",
    title: "見る",
    description: "フィードで進捗動画を見て、気になるプロジェクトを選ぶ。",
  },
  {
    id: "02",
    title: "選ぶ",
    description: "プランの内容・金額・配送見込みを確認して選択する。",
  },
  {
    id: "03",
    title: "支援する",
    description: "チェックアウトを完了し、支援履歴に反映される。",
  },
];

export default function HomePage() {
  return (
    <main className="page">
      <section className="hero" id="top">
        <div className="heroPanel">
          <div className="heroCopy">
            <p className="eyebrow">PROCESS-DRIVEN CROWDFUNDING</p>
            <h1>Build in public, back in public.</h1>
            <p className="lead">
              短尺動画で進捗を届け、応援につなげる購入型クラウドファンディング。
              発見から支援まで、モバイルでシンプルに完結します。
            </p>
            <div className="heroMeta">
              <a href="#detail" className="primaryButton">
                Waitlistに登録
              </a>
            </div>
          </div>

          <div className="heroArt" aria-hidden="true">
            <Image
              src="/hero-iphone.png"
              alt="iPhone preview"
              width={420}
              height={860}
              priority
            />
          </div>
        </div>
      </section>

      <section className="heroPoints">
        <h2>Key Points</h2>
        <div className="pointGrid">
          {keyPoints.map((item) => (
            <article className="pointCard" key={item.title}>
              <h3>{item.title}</h3>
              <p>{item.description}</p>
            </article>
          ))}
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
      </section>

      <footer className="footer">
        <div>
          <p className="logo">Lifecast</p>
          <p className="footerText">Process-driven crowdfunding platform.</p>
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
