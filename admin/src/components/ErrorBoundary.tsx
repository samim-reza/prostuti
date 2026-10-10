import { AlertTriangle, RotateCcw } from 'lucide-react';
import { Component, type ErrorInfo, type ReactNode } from 'react';

interface Props {
  children: ReactNode;
  /** Changing this value clears the error (e.g. the current pathname). */
  resetKey?: string;
  fullPage?: boolean;
}
interface State {
  error: Error | null;
  resetKey?: string;
}

/** Keeps one broken screen from blanking the whole console. */
export class ErrorBoundary extends Component<Props, State> {
  override state: State = { error: null, resetKey: this.props.resetKey };

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { error };
  }

  static getDerivedStateFromProps(props: Props, state: State): Partial<State> | null {
    if (props.resetKey !== state.resetKey) return { error: null, resetKey: props.resetKey };
    return null;
  }

  override componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('Console screen crashed', error, info.componentStack);
  }

  override render() {
    if (!this.state.error) return this.props.children;
    return (
      <div role="alert" className={this.props.fullPage ? 'flex min-h-dvh items-center justify-center p-6' : 'py-10'}>
        <div className="card mx-auto max-w-lg p-6 text-center">
          <AlertTriangle className="mx-auto size-8 text-danger" aria-hidden />
          <h1 className="mt-3 text-lg font-semibold text-fg">Something went wrong on this screen</h1>
          <p className="mt-1 text-sm text-muted">
            Nothing was changed. Reload to try again; if it keeps happening, report the message below.
          </p>
          <pre className="mt-3 max-h-40 overflow-auto rounded-lg bg-surface-2 p-2 text-left text-xs whitespace-pre-wrap text-fg-2">
            {this.state.error.message}
          </pre>
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="mt-4 inline-flex h-10 items-center gap-2 rounded-lg bg-brand px-4 text-sm font-medium text-brand-fg hover:bg-brand-strong"
          >
            <RotateCcw className="size-4" aria-hidden /> Reload
          </button>
        </div>
      </div>
    );
  }
}
