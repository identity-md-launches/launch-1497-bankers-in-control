import { useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react';
import type { Hash } from 'viem';
import {
  amount, charterAddress, checkEligibility, claimAddress, errorMessage, exactAmount, explorer,
  INSTANT, isExpectedClaim, network, parseId, publicClient, REST, robinhood, SHARE, shortAddress,
  submitClaim, switchChain, tokenAddress, verifyDeployment,
  type ChainState, type Eligibility, type Stage,
} from './chain';
import { Arrow, BankIcon, GoldenCuffs, LockIcon, WalletIcon } from './Artwork';
import { useWallet, type Wallet } from './wallet';

function Modal({ title, children, onClose }: { title: string; children: ReactNode; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const close = useRef(onClose); close.current = onClose;
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const dialog = ref.current!;
    dialog.showModal();
    const saved = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => { dialog.close(); document.body.style.overflow = saved; previous?.focus(); };
  }, []);
  return <dialog ref={ref} className="modal" aria-labelledby="dialog-title" onCancel={e => { e.preventDefault(); close.current(); }}>
    <div className="modal-heading"><h2 id="dialog-title">{title}</h2><button className="icon-button" aria-label="Close dialog" onClick={onClose}><span aria-hidden="true">×</span></button></div>
    {children}
  </dialog>;
}

function ExternalLink({ href, children, className = '' }: { href: string; children: ReactNode; className?: string }) {
  return <a className={`external-link ${className}`} href={href} target="_blank" rel="noopener noreferrer">{children}<Arrow diagonal /><span className="sr-only"> (opens in a new tab)</span></a>;
}

function ClaimPanel({ wallet, openWallet, chain, chainError, retry, checkingChain }: {
  wallet: Wallet; openWallet: () => void; chain: ChainState | null; chainError: string; retry: () => void; checkingChain: boolean;
}) {
  const [lookup, setLookup] = useState(false);
  const [input, setInput] = useState('');
  const [stage, setStage] = useState<Stage>('instant');
  const [result, setResult] = useState<Eligibility | null>(null);
  const [fieldError, setFieldError] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState<'check' | 'switch' | 'sign' | 'pending' | null>(null);
  const [review, setReview] = useState(false);
  const [tx, setTx] = useState<{ hash: Hash; confirmed: boolean; failed: boolean; eligibility: Eligibility } | null>(null);
  const sequence = useRef(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const txBusy = busy === 'sign' || busy === 'pending';
  const outstanding = Boolean(tx && !tx.confirmed && !tx.failed);
  const wrongChain = Boolean(wallet.account && wallet.chainId !== robinhood.id);

  useEffect(() => {
    ++sequence.current;
    setResult(null); setReview(false); setError('');
    setBusy(current => current === 'sign' || current === 'pending' ? current : null);
  }, [wallet.account, wallet.chainId]);
  useEffect(() => () => { ++sequence.current; }, []);

  function edit(value: string) {
    ++sequence.current; setInput(value); setResult(null); setFieldError(''); setError('');
    if (busy === 'check') setBusy(null);
  }
  function changeStage(next: Stage) {
    ++sequence.current; setStage(next); setResult(null); setFieldError(''); setError('');
    if (busy === 'check') setBusy(null);
  }
  async function check(event: FormEvent) {
    event.preventDefault();
    setError(''); setFieldError(''); setResult(null);
    let id: bigint;
    try { id = parseId(input); }
    catch (e) { setFieldError(errorMessage(e)); inputRef.current?.focus(); return; }
    const current = ++sequence.current;
    setBusy('check');
    try {
      const eligibility = await checkEligibility(id, stage, wallet.account);
      if (current === sequence.current) setResult(eligibility);
    } catch (e) { if (current === sequence.current) setError(errorMessage(e)); }
    finally { if (current === sequence.current) setBusy(null); }
  }
  async function changeNetwork() {
    if (!wallet.provider) return;
    setError(''); setBusy('switch');
    try { await switchChain(wallet.provider); await wallet.refresh(wallet.provider); }
    catch (e) { setError(errorMessage(e)); }
    finally { setBusy(null); }
  }
  async function confirm(hash: Hash, eligibility: Eligibility) {
    setBusy('pending'); setError('');
    try {
      const receipt = await publicClient.waitForTransactionReceipt({ hash, confirmations: 1, timeout: 120_000,
        onReplaced: replacement => {
          setTx({ hash: replacement.transaction.hash, confirmed: false, failed: replacement.reason === 'cancelled', eligibility });
        },
      });
      // A replacement is only a successful claim if it emitted our contract's Claimed event.
      const paid = receipt.status === 'success' && receipt.logs.some(log => isExpectedClaim(log, eligibility));
      setTx({ hash: receipt.transactionHash, confirmed: paid, failed: !paid, eligibility });
      if (!paid) setError('The transaction did not complete a claim. Check its details, then check eligibility before trying again.');
      setResult(null); retry();
    } catch { setError('The transaction was submitted, but confirmation is taking longer. Check its status before trying another claim.'); }
    finally { setBusy(null); }
  }
  async function send() {
    if (!result?.eligible || !wallet.provider || txBusy || outstanding) return;
    const eligibility = result;
    setReview(false); setBusy('sign'); setError(''); setTx(null);
    try {
      const hash = await submitClaim(wallet.provider, eligibility);
      setTx({ hash, confirmed: false, failed: false, eligibility });
      await confirm(hash, eligibility);
    } catch (e) { setError(errorMessage(e)); setResult(null); setBusy(null); }
  }

  return <section className="claim-panel" id="claim" aria-labelledby="claim-title">
    <div className="claim-heading"><h2 id="claim-title">Claim your BIC</h2><span className="coin-mark" aria-hidden="true">B</span></div>
    <p className="amount-label">Your share per eligible Charter</p>
    <p className="share-amount"><span>~{amount(SHARE)}</span> <span className="currency">BIC</span></p>
    <div className="claim-split">
      <div><span className="split-number">10%</span><span>Yours to claim</span></div>
      <LockIcon />
      <div><span className="split-number">90%</span><span>After you let go</span></div>
    </div>
    {!wallet.account && <>
      <button className="button primary connect-main" onClick={openWallet}><WalletIcon />Connect wallet<Arrow /></button>
      <p className="helper centered">Use the wallet that holds your Charter.</p>
    </>}
    {wallet.account && <div className="wallet-line"><span><span className="status-dot" />{shortAddress(wallet.account)}</span><button className="text-button" onClick={openWallet}>Manage wallet</button></div>}
    {wrongChain && <div className="notice warning"><p>Switch to Robinhood Chain to claim BIC.</p><button className="button secondary" disabled={Boolean(busy)} onClick={changeNetwork}>{busy === 'switch' ? 'Check your wallet…' : 'Switch network'}<Arrow /></button></div>}
    {!wallet.account && !lookup && <button className="text-button lookup-toggle" onClick={() => setLookup(true)}>Check a Charter ID <Arrow /></button>}
    {(wallet.account || lookup) && <div className="claim-workspace">
      <div className="stage-switch" aria-label="Claim stage"><button aria-pressed={stage === 'instant'} disabled={txBusy || outstanding} onClick={() => changeStage('instant')}>Claim 10%</button><button aria-pressed={stage === 'rest'} disabled={txBusy || outstanding} onClick={() => changeStage('rest')}>Release 90%</button></div>
      <form onSubmit={check} noValidate>
        <label htmlFor="charter-id">Charter ID</label>
        <div className="id-row"><input ref={inputRef} id="charter-id" name="charterId" type="text" inputMode="numeric" autoComplete="off" placeholder="e.g. 42" value={input} onChange={e => edit(e.target.value)} disabled={txBusy || outstanding} aria-invalid={Boolean(fieldError)} aria-describedby={fieldError ? 'id-error' : 'id-hint'} maxLength={12} /><button type="submit" className="button secondary" disabled={Boolean(busy) || outstanding || !chain}>{busy === 'check' ? 'Checking…' : 'Check ID'}<Arrow /></button></div>
        <p className="helper" id="id-hint">{stage === 'instant' ? 'Eligible IDs: 1–1,032. Check one ID at a time.' : 'Enter an ID you claimed with this same wallet.'}</p>
        {fieldError && <p className="error-text" id="id-error" role="alert">{fieldError}</p>}
      </form>
      <div className="result-region" aria-live="polite" aria-atomic="true">
        {busy === 'check' && <p className="helper">Reading this Charter’s claim status…</p>}
        {result && <div className={`eligibility ${result.eligible ? 'eligible' : ''}`}>
          <strong>{result.title}</strong><p>{result.detail}</p>
          {result.eligible && <><div className="payout"><span>Available for #{result.id.toString()}</span><strong title={exactAmount(result.amount) + ' BIC'}>~{amount(result.amount)} BIC</strong></div><button className="button primary" disabled={Boolean(busy) || wrongChain || !chain || outstanding} onClick={() => setReview(true)}>Review {stage === 'instant' ? 'claim' : 'release'}<Arrow /></button></>}
          {!result.eligible && !wallet.account && <button className="button secondary" onClick={openWallet}>Connect to check your wallet<Arrow /></button>}
          {result.charterBalance !== undefined && result.charterBalance > 0n && <a className="text-link" href="#handcuffs">Read before releasing your Charters <Arrow /></a>}
        </div>}
      </div>
    </div>}
    <div className="transaction-status" role="status" aria-live="polite" aria-atomic="true">
      {busy === 'sign' && <p className="notice">Checking eligibility, then requesting confirmation in your wallet. No token approvals are needed.</p>}
      {tx && <div className={`notice ${tx.confirmed ? 'success' : ''}`}>
        <strong>{tx.confirmed ? 'Claim confirmed. Welcome to the takeover.' : tx.failed ? 'Claim not completed.' : 'Transaction submitted.'}</strong>
        <p>{tx.confirmed ? `~${amount(tx.eligibility.amount)} BIC sent to ${shortAddress(tx.eligibility.account!)} for Charter #${tx.eligibility.id}.` : busy === 'pending' ? 'Waiting for confirmation on Robinhood Chain…' : 'Check the transaction status below.'}</p>
        <ExternalLink href={explorer('tx', tx.hash)}>View transaction</ExternalLink>
        {outstanding && busy !== 'pending' && <button className="button secondary" onClick={() => confirm(tx.hash, tx.eligibility)}>Check confirmation</button>}
        {tx.confirmed && tx.eligibility.stage === 'instant' && <p className="helper">Your remaining 90% stays assigned to this wallet. Read the release rules before burning or transferring any Charter.</p>}
      </div>}
    </div>
    {error && <p className="error-text" role="alert">{error}</p>}
    <div className="chain-status">
      {checkingChain ? <span>Checking Robinhood Chain…</span> : chain ? <span><span className="status-dot" />Robinhood Chain · Contracts verified</span> : <><span className="error-text">{chainError || 'Connection unavailable.'}</span><button className="text-button" onClick={retry}>Retry connection <Arrow /></button></>}
    </div>
    {review && result && <Modal title={stage === 'instant' ? 'Review your claim' : 'Review your release'} onClose={() => setReview(false)}>
      <p>{stage === 'instant' ? 'This records your wallet as the claimant for both portions of this Charter’s BIC.' : 'This pays the final portion for this Charter. Your wallet must still hold zero Charters when the transaction executes.'}</p>
      <dl className="review-details"><div><dt>Charter</dt><dd>#{result.id.toString()}</dd></div><div><dt>You receive</dt><dd>~{amount(result.amount)} BIC</dd></div><div><dt>Network</dt><dd>Robinhood Chain</dd></div><div><dt>Recipient</dt><dd className="address">{wallet.account}</dd></div><div><dt>Claim contract</dt><dd className="address">{claimAddress}</dd></div></dl>
      <p className="helper">Your wallet will show the ETH network fee. This transaction claims BIC; it does not burn or transfer your Charter.</p>
      <details className="exact-amount"><summary>Show exact token amount</summary><p>{exactAmount(result.amount)} BIC</p></details>
      <div className="modal-actions"><button className="button secondary" onClick={() => setReview(false)}>Cancel</button><button className="button primary" onClick={send}>Confirm in wallet<Arrow /></button></div>
    </Modal>}
  </section>;
}

const faqs = [
  { question: 'Which Charters qualify?', answer: <>Founding Charter IDs 1 through 1,032, inclusive. You must currently own the Charter for its first 10% claim. Each ID can receive each portion only once. Newer IDs above 1,032 do not receive BIC from this contract.</> },
  { question: 'Do I have to burn my Charter?', answer: <>The contract checks your wallet’s balance, not how a Charter left it. A transfer, burn or revocation can satisfy the zero-balance condition. All Charters must leave the original claimant wallet, including IDs above 1,032. Claim the first 10% before releasing an eligible Charter. This site does not execute NFT burns or transfers.</> },
  { question: 'Can the next holder claim my remaining BIC?', answer: <>No. The first claim permanently records the claimant wallet. The remaining 90% belongs to that wallet, even if the Charter is later transferred, burned or revoked. Keep access to the wallet that made the first claim.</> },
  { question: 'Is there a deadline or a lockup period?', answer: <>There is no deadline, cooldown or vesting clock in CharterClaim. The remaining 90% becomes claimable when the recorded claimant wallet holds zero Founding Charters. Receiving another Charter can block the release again until the wallet is empty.</> },
  { question: 'What does it cost to claim?', answer: <>There is no BIC claim fee and no token or NFT approval. You pay the Robinhood Chain network fee in ETH for each transaction. Your wallet shows that fee before you confirm. This interface handles one Charter ID per transaction.</> },
  { question: 'Can the Bankers change the rules?', answer: <>CharterClaim has no owner, admin, upgrade, withdrawal or recovery function. Unclaimed tokens remain in the contract. The Founding Charter collection is a separate contract; changes to its ownership or balance reporting can affect eligibility. BIC’s market value is not guaranteed.</> },
];

export function App() {
  const wallet = useWallet();
  const [walletOpen, setWalletOpen] = useState(false);
  const [chain, setChain] = useState<ChainState | null>(null);
  const [chainError, setChainError] = useState('');
  const [checkingChain, setCheckingChain] = useState(true);
  const [copied, setCopied] = useState(false);
  const [copyError, setCopyError] = useState('');
  const verificationSequence = useRef(0);
  const refresh = useCallback(async () => {
    const seq = ++verificationSequence.current;
    setCheckingChain(true); setChainError('');
    try { const state = await verifyDeployment(); if (seq === verificationSequence.current) setChain(state); }
    catch (e) { if (seq === verificationSequence.current) { setChain(null); setChainError(errorMessage(e)); } }
    finally { if (seq === verificationSequence.current) setCheckingChain(false); }
  }, []);
  useEffect(() => { void refresh(); return () => { ++verificationSequence.current; }; }, [refresh]);
  async function copyAddress() {
    try { await navigator.clipboard.writeText(tokenAddress); setCopied(true); setCopyError(''); }
    catch { setCopyError('Copy is unavailable in this browser. Select the full address below to copy it.'); }
  }
  function openWallet() { wallet.clearError(); setWalletOpen(true); }

  return <>
    <a className="skip-link" href="#claim">Skip to claim</a>
    <header className="site-header wrap">
      <a className="wordmark" href="#" aria-label="Bankers In Control home"><span className="brand-icon"><BankIcon /></span><span>Bankers<br />In Control<span className="wordmark-dot">.</span></span></a>
      <nav aria-label="Main navigation"><a href="#how-it-works">The deal</a><a href="#allocation">Tokenomics</a><a href="#questions">Questions</a></nav>
      <button className="header-wallet" onClick={openWallet}><WalletIcon /><span>{wallet.account ? shortAddress(wallet.account) : 'Connect wallet'}</span></button>
    </header>
    <main>
      <section className="hero wrap" aria-labelledby="hero-title">
        <div className="hero-story">
          <h1 id="hero-title">Claim BIC.<br /><span>Break the cuffs.</span></h1>
          <p className="hero-description">A two-stage BIC token claim for Founding Charter holders.</p>
          <div className="hero-art"><GoldenCuffs /><p>The Bankers are taking over.<br />Your exit package is looking golden.</p></div>
        </div>
        <ClaimPanel wallet={wallet} openWallet={openWallet} chain={chain} chainError={chainError} retry={() => void refresh()} checkingChain={checkingChain} />
        <div className="hero-footnote"><span><BankIcon />Bankers In Control</span><span>1,032 eligible Charters</span><span>One very golden dilemma</span></div>
      </section>

      <section className="how-section" id="how-it-works" aria-labelledby="how-title"><div className="wrap">
        <div className="section-heading"><h2 id="how-title">The deal behind<br />the handshake.</h2><p>The Bankers made you an offer: a little BIC for holding on, a lot more for letting go.</p></div>
        <ol className="steps">
          <li><span className="step-number" aria-hidden="true">01</span><h3>Bring your Charter</h3><p>Connect the wallet holding a Founding Charter, ID 1–1,032. Enter its ID to check eligibility.</p><span className="step-caption">Your seat at the table</span></li>
          <li><span className="step-number" aria-hidden="true">02</span><h3>Take the first 10%</h3><p>Claim ~{amount(INSTANT)} BIC per eligible ID. Your wallet is recorded for the remaining share.</p><span className="step-caption">The golden handshake</span></li>
          <li><span className="step-number" aria-hidden="true">03</span><h3>Let go. Claim the rest.</h3><p>Once that wallet holds no Charters, return to release the remaining ~{amount(REST)} BIC per claimed ID.</p><span className="step-caption">The golden handcuffs</span></li>
        </ol>
      </div></section>

      <section className="handcuffs-section wrap" id="handcuffs" aria-labelledby="handcuffs-title">
        <div className="handcuffs-intro"><div className="seal" aria-hidden="true"><LockIcon unlocked /></div><h2 id="handcuffs-title">Read the<br />golden fine print.</h2><p>The Bankers would love a dramatic Charter bonfire. Read the deal before you strike a match.</p></div>
        <div className="fine-print">
          <div><span className="rule-symbol" aria-hidden="true">01</span><div><h3>Claim first. Burn later.</h3><p>Burning an unclaimed Charter can leave its BIC unclaimable. Secure the first 10% before releasing an eligible ID. A burn is irreversible.</p></div></div>
          <div><span className="rule-symbol" aria-hidden="true">02</span><div><h3>Zero means every Charter.</h3><p>The remaining 90% requires a total Charter balance of zero, including IDs above 1,032. A transfer, burn or revocation can satisfy this condition.</p></div></div>
          <div><span className="rule-symbol" aria-hidden="true">03</span><div><h3>Your wallet keeps the claim.</h3><p>The BIC follows the original claimant wallet, not the NFT. Keep your wallet keys. Come back with that same wallet for the remainder.</p></div></div>
          <p className="helper">CharterClaim cannot burn NFTs. Manage Charters through the collection’s own contract and verify any action in your wallet.</p>
          <ExternalLink href={explorer('address', charterAddress)}>View the Founding Charter contract</ExternalLink>
        </div>
      </section>

      <section className="allocation-section" id="allocation" aria-labelledby="allocation-title"><div className="wrap allocation-grid">
        <div><h2 id="allocation-title">A billion BIC<br />to go around.</h2><p>A fixed supply of 1,000,000,000 BIC on Robinhood Chain, paired with IMD.</p><div className="allocation-bar" role="img" aria-label="80% Charter claims, 10% BIC/IMD pool, 10% swarm"><span /><span /><span /></div><p className="helper">The claim contract has no owner or admin.</p></div>
        <dl className="allocation-list"><div><dt><span className="allocation-dot charter" />Charter holders</dt><dd><strong>80%</strong><span>800,000,000 BIC</span></dd></div><div><dt><span className="allocation-dot pool" />BIC / IMD pool</dt><dd><strong>10%</strong><span>100,000,000 BIC</span></dd></div><div><dt><span className="allocation-dot swarm" />The swarm</dt><dd><strong>10%</strong><span>100,000,000 BIC</span></dd></div></dl>
      </div></section>

      <section className="questions-section wrap" id="questions" aria-labelledby="questions-title"><div><h2 id="questions-title">Questions for<br />the Bankers?</h2><p>It pays to read the fine print.</p><a className="text-link" href="#claim">Back to your claim <Arrow /></a></div><div className="faq-list">{faqs.map(faq => <details key={faq.question}><summary>{faq.question}<span className="plus" aria-hidden="true" /></summary><p>{faq.answer}</p></details>)}</div></section>

      <section className="contracts-section wrap" aria-labelledby="contracts-title"><div className="contracts-heading"><h2 id="contracts-title">Check the books.</h2><p>Every contract is open to inspection.</p></div><div className="contract-row"><div><span className="helper">BIC token · Robinhood Chain</span><p className="address">{tokenAddress}</p></div><div className="contract-actions"><button className="button secondary" onClick={copyAddress}>{copied ? 'Copied' : 'Copy address'}</button><ExternalLink href={explorer('address', tokenAddress)}>View token</ExternalLink></div></div><div className="contract-row"><div><span className="helper">CharterClaim · No owner or admin</span><p className="address">{claimAddress}</p></div><ExternalLink href={explorer('address', claimAddress)}>View claim contract</ExternalLink></div><p className="helper contract-balance">{chain ? `Claim contract balance: ${amount(chain.reserve)} BIC · Read at block ${chain.block.toLocaleString('en-US')}.` : 'Live contract balance is unavailable until the network check completes.'} <button className="text-button" disabled={checkingChain} onClick={() => void refresh()}>{checkingChain ? 'Refreshing…' : 'Refresh'}</button></p><div role="status" className="sr-only">{copied ? 'Token address copied to clipboard.' : ''}</div>{copyError && <p className="error-text" role="alert">{copyError}</p>}</section>
    </main>
    <footer className="site-footer wrap"><a className="footer-brand" href="#"><BankIcon />Bankers In Control</a><p>Golden handcuffs. Your call.</p><a href="#claim">Claim BIC <Arrow /></a><p className="footer-note">BIC is a token, not a bank account. Claims do not guarantee market value. Displayed token amounts are rounded down; the contract pays exact amounts.</p></footer>

    {walletOpen && <Modal title={wallet.account ? 'Your wallet' : 'Connect your wallet'} onClose={() => setWalletOpen(false)}>
      {wallet.account ? <><p className="address wallet-address">{wallet.account}</p><p>{wallet.chainId === robinhood.id ? network.network.name : 'Your wallet is on a different network.'}</p><p className="helper">Change accounts in your wallet to use another Charter holder.</p><button className="button secondary full-width" onClick={() => { wallet.disconnect(); setWalletOpen(false); }}>Disconnect site</button></> : <>
        <p>Connect the wallet that holds your Founding Charter. Connecting does not send a transaction.</p>
        {wallet.choices.length ? <div className="wallet-options">{wallet.choices.map(w => <button className="button secondary" key={w.info.uuid} disabled={wallet.connecting} onClick={async () => { if (await wallet.connect(w.provider)) setWalletOpen(false); }}><WalletIcon />{wallet.connecting ? 'Open your wallet…' : w.info.name}<Arrow /></button>)}</div> : <div className="notice"><strong>No browser wallet found.</strong><p>Open this site in your wallet’s built-in browser, or enable an Ethereum-compatible browser wallet extension and reload this page.</p><button className="button secondary" onClick={() => window.location.reload()}>Reload page</button></div>}
        <p className="helper">Use Robinhood Chain (4663). You will need ETH for claim transaction fees.</p>
      </>}
      {wallet.error && <p className="error-text" role="alert">{wallet.error}</p>}
    </Modal>}
  </>;
}
