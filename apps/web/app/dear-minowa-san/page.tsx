import type { Metadata } from "next";
import Image from "next/image";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "Dear Minowa-san | Lifecast",
  description:
    "投資家・箕輪厚介さんへ。Lifecastが求められる理由、関わってほしい理由、そして私たちがやるべき理由をまとめたページ。",
};

const whyNowItems = [
  {
    title: "1. ショート動画のプロセスエコノミー",
    body: "フォローやいいねで応援する行動は、すでに習慣化しています。ショート動画はプロセスを伝えるのに最適なフォーマットであり、それを起点に資金調達まで完結する体験はユーザーにとって自然で魅力的です。",
  },
  {
    title: "2. 推し活文化の本格化",
    body: "人は推しにお金を使います。それは単なる消費ではなく、自己表現と自己実現の一部だからです。だからこそ『応援行為』を設計し、それを可視化できるプロダクトが強い。",
  },
  {
    title: "3. 既存プラットフォームの課題",
    body: "既存のクラウドファンディングは、プロジェクト発見が困難で、プロセスに関与しづらく、クリエイターの人柄が伝わりにくいです。これらの課題を解決するプロダクトはまだ存在していません。",
  },
  {
    title: "4. 人間性への回帰",
    body: "AIやテクノロジーを利用して簡単に物やサービスを作れるようになった今、『何を作るか』だけでなく『誰が作るか』が選ばれる時代です。開発者の人格や信念が伝わるほど、支援は生まれやすくなります。",
  },
];

const researchFacts = [
  "SNS経由でクラファンを発見する比率は55%（三菱UFJリサーチ＆コンサルティング, 2020）",
  "動画ありのCF成功率が「50%」・動画なしが「30%」（Kickstarter公式ブログ, 2012）",
  "ショート動画視聴者の32.2%が視聴後に商品購入経験あり（MMD研究所, 2023）",
];

const whoWeAreIntro =
  "私たちはカナダのブリティッシュコロンビア大学（UBC）でコンピュータサイエンスを専攻している、23歳の大学生です。ソフトウェアエンジニアとして開発を数年間行ってきて、企業と協力してAIの研究開発にも取り組んでいます。";

const currentWorks = [
  {
    title: "シンギュラーラジオ（AIポッドキャスト）",
    url: "https://www.youtube.com/@SingularRadio",
    note: "AI活用から論文解説まで、AIの本質的な情報を広く伝えるためのポッドキャストとそのコミュニティを運営しています。"
  },
  {
    title: "ボードゲーム『Laplace』",
    url: "https://www.laplace.zone",
    note: "AI時代をテーマにした2v2戦略ボードゲームを企画・開発しています。物理版をクラウドファンディング実施予定です。"
  },
  {
    title: "AI関連の研究開発",
    url: "",
    note: "スポーツやリサーチなど、私たちの知見を活かせる分野で、企業と協力してAIの研究開発を行っています。"
  }
];

const visionSections = [
  {
    title: "1. 日本発グローバルプラットフォームを作る",
    paragraphs: [
      "私たちの第一のビジョンは、日本発のグローバルプラットフォームを作ることです。AIで制作コストが下がる時代に希少になるのは、アウトプット単体ではなく、積み上げられた歴史と人格です。継続的な制作ログ、時間をかけて育つキャラクター、作り手の一貫した物語は短期で模倣できません。",
      "日本が強みとしてきた連載文化・IP運用・推し文化は、この時代の価値構造と一致しています。さらに、日本のアニメやキャラクター、美学は言語に依存せず世界で受容されてきた実績があり、ショート動画はその発見と拡散を加速させる分配装置になります。",
      "勝つプラットフォームは例外なく、その上に載るコンテンツが強い。物語と推しの領域において、日本はキャラクター駆動型IPと長期的ファン関係の構築で構造的優位を持ち、米中とも十分に競争可能だと考えています。",
    ],
  },
  {
    title: "2. 応援が価値になる新しい経済を作る",
    paragraphs: [
      "クラウドファンディングやDAO、株式の小口化によって、『プロジェクトを支援し、見返りを得る』構造はすでに一般化しました。支援は富裕層だけの行為ではなく、より多くの人が参加できる行為になっています。",
      "一方で今の仕組みには、高サイクル性が足りません。良いプロジェクトを素早く見つけ、自分の行動で押し上げ、影響を実感する循環が弱い。支援はできても、発見と増幅の速度が遅く、個人の関与実感が薄いのが課題です。",
      "Lifecastはこの空白を埋めます。出発点は購入型クラウドファンディングですが、目指すのは『応援が可視化され、増幅され、循環する場』です。SNSが得意な認知拡大だけで終わらず、応援と参加が継続する基盤を作る。将来的には金銭中心の評価軸を相対化し、人とのつながりやコミュニティへの関与が価値の基準となる新しい経済の前提を構築しようとする試みです。",
    ],
  },
];

const whyMinowaItems = [
  "社会や人間に対する解像度が高く、まだ他の人が気づいていない「時代の空気」を言語化できる方だと感じています。私たちが作ろうとしているのは機能だけのサービスではなく、人の感情や行動に深く関わるプラットフォームなので、箕輪さんの洞察力は大きな力になります。",
  "経営者・投資家・クリエイターを横断する人脈を持ち、領域を越えて人をつなげられる点にも大きな価値があります。初速を作るだけでなく、次の打ち手を連続的に生み出すうえで、箕輪さんの関与は決定的だと考えています。",
  "何よりも個人的に強くリスペクトしており、発信を見続ける中で何度も学ばせてもらってきました。私がこのアイデアを思いついたのも、箕輪さんの本や動画から得たインプットの積み重ねによるところも大いにあると思います。冷奴チャンネルや人間エネルギーカードなど、箕輪さんならではの独特な発想も大好きです。私からの感謝の気持ちも込めて、ぜひこの会社の株式を持っていただきたいと思っています。",
];

export default function DearMinowaPage() {
  return (
    <main className={styles.page}>
      <section className="hero" id="top">
        <div className="heroPanel">
          <div className="heroCopy">
            <p className="eyebrow">DEAR MINOWA-SAN</p>
            <h1 className={styles.dearTitle}>箕輪厚介さんへ</h1>
            <p className="lead">
              Lifecastは、ショート動画×プロセスエコノミーに最適化されたクラウドファンディングプラットフォームです。
              日本発のグローバルプラットフォームとして、起業と資金調達の常識をアップデートしたいと考えています。
            </p>
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

      <section className={styles.section} id="who-we-are">
        <h2>なぜショート動画型クラウドファンディングが来るのか</h2>
        <div className={styles.grid}>
          {whyNowItems.map((item) => (
            <article key={item.title} className={styles.card}>
              <h3>{item.title}</h3>
              <p>{item.body}</p>
            </article>
          ))}
        </div>
        <ul className={styles.facts}>
          {researchFacts.map((fact) => (
            <li key={fact}>{fact}</li>
          ))}
        </ul>
      </section>

      <section className={styles.section}>
        <h2>私たちは誰か</h2>
        <div className={`${styles.visionBlock} ${styles.flatBlock}`}>
          <section className={styles.visionSection}>
            <p>{whoWeAreIntro}</p>

            <h3 className={styles.subheading}>今やっていること</h3>
            <ul className={styles.workList}>
              {currentWorks.map((work) => (
                <li key={work.title} className={styles.workItem}>
                  {work.url ? (
                    <a href={work.url} target="_blank" rel="noreferrer" className={styles.workTitle}>
                      {work.title}
                    </a>
                  ) : (
                    <span className={styles.workTitle}>{work.title}</span>
                  )}
                  <p>{work.note}</p>
                </li>
              ))}
            </ul>

            <h3 className={`${styles.subheading} ${styles.videoHeading}`}>
              自己紹介とアプリのデモ動画です！（3分）
            </h3>
            <div className={styles.videoWrap}>
              <iframe
                className={styles.videoFrame}
                src="https://www.youtube.com/embed/M7lc1UVf-VE"
                title="Temporary YouTube placeholder"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                referrerPolicy="strict-origin-when-cross-origin"
                allowFullScreen
              />
            </div>
          </section>
        </div>
      </section>

      <section className={styles.section}>
        <h2>私たちのビジョン</h2>
        <div className={styles.visionBlock}>
          {visionSections.map((section) => (
            <section key={section.title} className={styles.visionSection}>
              <h3>{section.title}</h3>
              {section.paragraphs.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
            </section>
          ))}
        </div>
      </section>

      <section className={styles.section}>
        <h2>なぜ、箕輪さんに関わってほしいのか</h2>
        <ul className={styles.list}>
          {whyMinowaItems.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
      </section>

      <section className={styles.closing}>
        <h2>最後に</h2>
        <p>
          最後までお読みいただき、ありがとうございます。
          もし少しでもご興味を持っていただけたら、今後の関わり方について、チャットでも構いませんので一度お話しさせてください。
          私たちはまだアイデア・デモ段階ですが、箕輪さんとともにLifecastを世界に通用するプラットフォームへ育て、応援社会の当たり前を作り上げていきたいと考えています。
          <a href="https://x.com/dancing_amigo" target="_blank" rel="noreferrer">
            XのDM（@dancing_amigo）
          </a>
          、または
          <a href="mailto:htakeshi0614@gmail.com">
            メール（htakeshi0614@gmail.com）
          </a>
          までご連絡いただけますと幸いです。
          どうぞよろしくお願いいたします。
        </p>
      </section>
    </main>
  );
}
