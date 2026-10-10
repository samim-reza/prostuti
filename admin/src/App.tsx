import { ShieldAlert } from 'lucide-react';
import { lazy, Suspense, type ReactNode } from 'react';
import { Navigate, Route, Routes, useLocation } from 'react-router';
import { useAuth, useStaff } from './auth/AuthProvider';
import { LoginPage } from './auth/LoginPage';
import { ErrorBoundary } from './components/ErrorBoundary';
import { EmptyState, Spinner } from './components/ui';
import { AppShell } from './layout/AppShell';
import { env } from './lib/env';

const DashboardPage = lazy(() => import('./pages/DashboardPage'));
const UsersPage = lazy(() => import('./pages/users/UsersPage'));
const QuestionsPage = lazy(() => import('./pages/questions/QuestionsPage'));
const ModerationPage = lazy(() => import('./pages/ModerationPage'));
const CurrentAffairsPage = lazy(() => import('./pages/current/CurrentAffairsPage'));
const NewsSourcesPage = lazy(() => import('./pages/current/NewsSourcesPage'));
const PipelinePage = lazy(() => import('./pages/current/PipelinePage'));
const SchedulesPage = lazy(() => import('./pages/SchedulesPage'));
const TracksPage = lazy(() => import('./pages/TracksPage'));
const AddonsPage = lazy(() => import('./pages/monetization/AddonsPage'));
const PromosPage = lazy(() => import('./pages/monetization/PromosPage'));
const ConfigPage = lazy(() => import('./pages/ConfigPage'));
const BroadcastPage = lazy(() => import('./pages/BroadcastPage'));
const ErrorsPage = lazy(() => import('./pages/monitoring/ErrorsPage'));
const AiUsagePage = lazy(() => import('./pages/monitoring/AiUsagePage'));
const AuditPage = lazy(() => import('./pages/monitoring/AuditPage'));

/** Hides admin-only screens from moderators (the RPCs enforce it anyway). */
function AdminOnly({ children }: { children: ReactNode }) {
  const staff = useStaff();
  if (staff.role !== 'admin') return <Navigate to="/moderation" replace />;
  return <>{children}</>;
}

function ConfigError({ message }: { message: string }) {
  return (
    <main className="flex min-h-dvh items-center justify-center p-6">
      <div className="card max-w-lg p-6">
        <EmptyState title="The console is not configured" icon={<ShieldAlert className="size-8 text-danger" />}>
          {message}
        </EmptyState>
      </div>
    </main>
  );
}

export function App() {
  const { state } = useAuth();
  const location = useLocation();
  if (env.error) return <ConfigError message={env.error} />;
  if (state.status === 'loading') return <Spinner label="Checking your session" className="min-h-dvh" />;
  if (state.status === 'signed_out') return <LoginPage />;

  return (
    <AppShell>
      <ErrorBoundary resetKey={location.pathname}>
        <Suspense fallback={<Spinner />}>
          <Routes>
            <Route path="/" element={state.profile.role === 'admin' ? <DashboardPage /> : <Navigate to="/moderation" replace />} />
            <Route path="/questions" element={<QuestionsPage />} />
            <Route path="/moderation" element={<ModerationPage />} />
            <Route
              path="/users"
              element={
                <AdminOnly>
                  <UsersPage />
                </AdminOnly>
              }
            />
            <Route
              path="/current-affairs"
              element={
                <AdminOnly>
                  <CurrentAffairsPage />
                </AdminOnly>
              }
            />
            <Route
              path="/current-affairs/sources"
              element={
                <AdminOnly>
                  <NewsSourcesPage />
                </AdminOnly>
              }
            />
            <Route
              path="/current-affairs/pipeline"
              element={
                <AdminOnly>
                  <PipelinePage />
                </AdminOnly>
              }
            />
            <Route
              path="/schedules"
              element={
                <AdminOnly>
                  <SchedulesPage />
                </AdminOnly>
              }
            />
            <Route
              path="/tracks"
              element={
                <AdminOnly>
                  <TracksPage />
                </AdminOnly>
              }
            />
            <Route
              path="/monetization"
              element={
                <AdminOnly>
                  <AddonsPage />
                </AdminOnly>
              }
            />
            <Route
              path="/monetization/promos"
              element={
                <AdminOnly>
                  <PromosPage />
                </AdminOnly>
              }
            />
            <Route
              path="/config"
              element={
                <AdminOnly>
                  <ConfigPage />
                </AdminOnly>
              }
            />
            <Route
              path="/broadcast"
              element={
                <AdminOnly>
                  <BroadcastPage />
                </AdminOnly>
              }
            />
            <Route
              path="/monitoring/errors"
              element={
                <AdminOnly>
                  <ErrorsPage />
                </AdminOnly>
              }
            />
            <Route
              path="/monitoring/ai"
              element={
                <AdminOnly>
                  <AiUsagePage />
                </AdminOnly>
              }
            />
            <Route
              path="/monitoring/audit"
              element={
                <AdminOnly>
                  <AuditPage />
                </AdminOnly>
              }
            />
            <Route path="/login" element={<Navigate to="/" replace />} />
            <Route
              path="*"
              element={
                <EmptyState title="Page not found">
                  The page you are looking for doesn't exist. Use the navigation to find your way.
                </EmptyState>
              }
            />
          </Routes>
        </Suspense>
      </ErrorBoundary>
    </AppShell>
  );
}
