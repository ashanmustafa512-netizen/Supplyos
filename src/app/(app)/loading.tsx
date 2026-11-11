export default function WorkspaceLoading() {
  return (
    <div className="page-stack workspace-loading" role="status" aria-live="polite" aria-label="Loading workspace">
      <span className="sr-only">Loading workspace content…</span>
      <div className="page-heading-row">
        <div className="workspace-loading-heading">
          <span className="loading-skeleton loading-eyebrow" />
          <span className="loading-skeleton loading-title" />
          <span className="loading-skeleton loading-description" />
        </div>
      </div>
      <div className="metric-grid metric-grid-four">
        {Array.from({ length: 4 }, (_, index) => (
          <div className="metric-card workspace-loading-card" key={index}>
            <span className="loading-skeleton loading-card-label" />
            <span className="loading-skeleton loading-card-value" />
            <span className="loading-skeleton loading-card-foot" />
          </div>
        ))}
      </div>
      <section className="panel workspace-loading-panel">
        <span className="loading-skeleton loading-panel-title" />
        {Array.from({ length: 5 }, (_, index) => (
          <span className="loading-skeleton loading-row" key={index} />
        ))}
      </section>
    </div>
  );
}
