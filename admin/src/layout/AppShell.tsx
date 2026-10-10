import {
  Activity,
  BookOpen,
  Bot,
  CalendarClock,
  ClipboardList,
  CreditCard,
  FileQuestion,
  KeyRound,
  LayoutDashboard,
  LogOut,
  Megaphone,
  Menu,
  Monitor,
  Moon,
  Newspaper,
  ScrollText,
  Settings2,
  ShieldAlert,
  Sun,
  Ticket,
  Users,
  X,
} from 'lucide-react';
import { useEffect, useState, type ComponentType, type ReactNode } from 'react';
import { NavLink, useLocation } from 'react-router';
import { useAuth, useStaff } from '../auth/AuthProvider';
import { ChangePasswordDialog } from '../auth/ChangePasswordDialog';
import { Avatar, cx, IconButton } from '../components/ui';

interface NavItem {
  to: string;
  label: string;
  icon: ComponentType<{ className?: string }>;
  adminOnly?: boolean;
  end?: boolean;
}
interface NavGroup {
  label: string;
  items: NavItem[];
}

export const NAV: NavGroup[] = [
  {
    label: 'Overview',
    items: [{ to: '/', label: 'Dashboard', icon: LayoutDashboard, adminOnly: true, end: true }],
  },
  {
    label: 'Content',
    items: [
      { to: '/questions', label: 'Questions', icon: FileQuestion },
      { to: '/moderation', label: 'Moderation', icon: ShieldAlert },
      { to: '/current-affairs', label: 'Current affairs', icon: Newspaper, adminOnly: true },
      { to: '/schedules', label: 'Exam schedules', icon: CalendarClock, adminOnly: true },
      { to: '/tracks', label: 'Exam tracks', icon: ClipboardList, adminOnly: true },
    ],
  },
  {
    label: 'People & money',
    items: [
      { to: '/users', label: 'Users', icon: Users, adminOnly: true },
      { to: '/monetization', label: 'Add-ons', icon: CreditCard, adminOnly: true, end: true },
      { to: '/monetization/promos', label: 'Promo codes', icon: Ticket, adminOnly: true },
      { to: '/broadcast', label: 'Broadcast', icon: Megaphone, adminOnly: true },
    ],
  },
  {
    label: 'System',
    items: [
      { to: '/config', label: 'App config', icon: Settings2, adminOnly: true },
      { to: '/monitoring/errors', label: 'Client errors', icon: Activity, adminOnly: true },
      { to: '/monitoring/ai', label: 'AI usage', icon: Bot, adminOnly: true },
      { to: '/monitoring/audit', label: 'Audit log', icon: ScrollText, adminOnly: true },
    ],
  },
];

type ThemePref = 'light' | 'dark' | 'system';
const THEME_KEY = 'prostuti-admin-theme';

function readTheme(): ThemePref {
  try {
    const v = localStorage.getItem(THEME_KEY);
    return v === 'light' || v === 'dark' ? v : 'system';
  } catch {
    return 'system';
  }
}

function applyTheme(pref: ThemePref) {
  const dark = pref === 'dark' || (pref === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.classList.toggle('dark', dark);
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
}

function useTheme(): [ThemePref, (p: ThemePref) => void] {
  const [pref, setPref] = useState<ThemePref>(readTheme);
  useEffect(() => {
    applyTheme(pref);
    try {
      localStorage.setItem(THEME_KEY, pref);
    } catch {
      /* storage unavailable */
    }
    if (pref !== 'system') return;
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = () => applyTheme('system');
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, [pref]);
  return [pref, setPref];
}

function ThemeToggle() {
  const [pref, setPref] = useTheme();
  const next: Record<ThemePref, ThemePref> = { system: 'light', light: 'dark', dark: 'system' };
  const Icon = pref === 'light' ? Sun : pref === 'dark' ? Moon : Monitor;
  return (
    <IconButton label={`Theme: ${pref} (switch to ${next[pref]})`} onClick={() => setPref(next[pref])}>
      <Icon className="size-4.5" />
    </IconButton>
  );
}

function Sidebar({ onNavigate }: { onNavigate?: () => void }) {
  const staff = useStaff();
  const isAdmin = staff.role === 'admin';
  return (
    <nav aria-label="Main" className="flex flex-col gap-5 px-3 py-4">
      {NAV.map((group) => {
        const items = group.items.filter((i) => isAdmin || !i.adminOnly);
        if (!items.length) return null;
        return (
          <div key={group.label}>
            <p className="mb-1 px-2.5 text-[0.6875rem] font-semibold tracking-wider text-muted uppercase">{group.label}</p>
            <ul className="space-y-0.5">
              {items.map((item) => (
                <li key={item.to}>
                  <NavLink
                    to={item.to}
                    end={item.end}
                    onClick={onNavigate}
                    className={({ isActive }) =>
                      cx(
                        'flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-sm font-medium transition-colors',
                        isActive ? 'bg-brand-soft text-brand-strong dark:text-brand' : 'text-fg-2 hover:bg-surface-2 hover:text-fg',
                      )
                    }
                  >
                    <item.icon className="size-4.5 shrink-0" />
                    {item.label}
                  </NavLink>
                </li>
              ))}
            </ul>
          </div>
        );
      })}
    </nav>
  );
}

function Brand() {
  return (
    <div className="flex items-center gap-2.5">
      <img src="/favicon.svg" alt="" width={28} height={28} className="rounded-lg" />
      <div className="leading-tight">
        <p className="text-sm font-semibold text-fg">Prostuti Admin</p>
        <p className="text-[0.6875rem] text-muted" lang="bn">
          প্রস্তুতি কনসোল
        </p>
      </div>
    </div>
  );
}

function UserMenu() {
  const staff = useStaff();
  const { signOut } = useAuth();
  const [open, setOpen] = useState(false);
  const [pwOpen, setPwOpen] = useState(false);
  const name = staff.full_name || staff.username || staff.email;

  useEffect(() => {
    if (!open) return;
    const close = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false);
    window.addEventListener('keydown', close);
    return () => window.removeEventListener('keydown', close);
  }, [open]);

  return (
    <div className="relative">
      <button
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-2 rounded-lg px-1.5 py-1 hover:bg-surface-2"
      >
        <Avatar name={name} url={staff.avatar_url} size={30} />
        <span className="hidden text-left leading-tight sm:block">
          <span className="block max-w-40 truncate text-sm font-medium text-fg">{name}</span>
          <span className="block text-[0.6875rem] text-muted capitalize">{staff.role}</span>
        </span>
      </button>
      {open ? (
        <>
          <div className="fixed inset-0 z-30" aria-hidden onClick={() => setOpen(false)} />
          <div role="menu" className="absolute right-0 z-40 mt-1 w-56 rounded-xl border border-line bg-surface p-1 shadow-card">
            <div className="border-b border-line px-3 py-2">
              <p className="truncate text-sm font-medium text-fg">{name}</p>
              <p className="truncate text-xs text-muted">{staff.email}</p>
            </div>
            <button
              role="menuitem"
              type="button"
              className="mt-1 flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-fg-2 hover:bg-surface-2"
              onClick={() => {
                setOpen(false);
                setPwOpen(true);
              }}
            >
              <KeyRound className="size-4" /> Change password
            </button>
            <button
              role="menuitem"
              type="button"
              className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-danger hover:bg-danger-soft"
              onClick={() => void signOut()}
            >
              <LogOut className="size-4" /> Sign out
            </button>
          </div>
        </>
      ) : null}
      <ChangePasswordDialog open={pwOpen} onClose={() => setPwOpen(false)} />
    </div>
  );
}

export function AppShell({ children }: { children: ReactNode }) {
  const [mobileOpen, setMobileOpen] = useState(false);
  const location = useLocation();
  useEffect(() => setMobileOpen(false), [location.pathname]);
  useEffect(() => {
    if (!mobileOpen) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setMobileOpen(false);
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [mobileOpen]);

  return (
    <div className="min-h-dvh bg-bg">
      <a href="#main" className="sr-only z-50 rounded-lg bg-surface px-3 py-2 focus:not-sr-only focus:fixed focus:top-2 focus:left-2">
        Skip to content
      </a>
      {/* desktop sidebar */}
      <aside className="fixed inset-y-0 left-0 z-20 hidden w-60 flex-col border-r border-line bg-surface lg:flex">
        <div className="flex h-14 items-center border-b border-line px-4">
          <Brand />
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto">
          <Sidebar />
        </div>
      </aside>
      {/* mobile drawer */}
      {mobileOpen ? (
        <div className="fixed inset-0 z-40 lg:hidden" role="dialog" aria-modal="true" aria-label="Navigation">
          <div className="absolute inset-0 bg-black/50" onClick={() => setMobileOpen(false)} aria-hidden />
          <div className="absolute inset-y-0 left-0 flex w-72 max-w-[85vw] flex-col bg-surface shadow-card">
            <div className="flex h-14 items-center justify-between border-b border-line px-4">
              <Brand />
              <IconButton label="Close navigation" autoFocus onClick={() => setMobileOpen(false)}>
                <X className="size-5" />
              </IconButton>
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto">
              <Sidebar onNavigate={() => setMobileOpen(false)} />
            </div>
          </div>
        </div>
      ) : null}
      <div className="lg:pl-60">
        <header className="sticky top-0 z-10 flex h-14 items-center justify-between gap-2 border-b border-line bg-surface/90 px-3 backdrop-blur sm:px-5">
          <div className="flex items-center gap-2">
            <IconButton label="Open navigation" className="lg:hidden" onClick={() => setMobileOpen(true)}>
              <Menu className="size-5" />
            </IconButton>
            <div className="lg:hidden">
              <Brand />
            </div>
          </div>
          <div className="flex items-center gap-1">
            <a
              href="https://github.com/samim-reza/prostuti/blob/main/docs/ADMIN.md"
              target="_blank"
              rel="noreferrer"
              className="hidden items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-sm text-muted hover:bg-surface-2 hover:text-fg sm:inline-flex"
            >
              <BookOpen className="size-4" /> Docs
            </a>
            <ThemeToggle />
            <UserMenu />
          </div>
        </header>
        <main id="main" className="mx-auto w-full max-w-[1400px] px-4 py-6 sm:px-6">
          {children}
        </main>
      </div>
    </div>
  );
}
