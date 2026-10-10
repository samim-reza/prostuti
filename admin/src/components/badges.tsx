import { CheckCircle2, Flag, HelpCircle } from 'lucide-react';
import type { QuestionStatus, ReviewStatus } from '../lib/types';
import { Badge } from './ui';

export function RoleBadge({ role }: { role: string }) {
  if (role === 'admin') return <Badge tone="brand">admin</Badge>;
  if (role === 'moderator') return <Badge tone="info">moderator</Badge>;
  return <Badge>user</Badge>;
}

export function StatusBadge({ status }: { status: QuestionStatus | string }) {
  const tone = status === 'published' ? 'success' : status === 'draft' ? 'info' : status === 'rejected' ? 'danger' : 'neutral';
  return <Badge tone={tone}>{status}</Badge>;
}

/** Review state always pairs colour with an icon + label (never colour alone). */
export function ReviewBadge({ review }: { review: ReviewStatus | string }) {
  if (review === 'verified') {
    return (
      <Badge tone="success" icon={<CheckCircle2 className="size-3" aria-hidden />}>
        verified
      </Badge>
    );
  }
  if (review === 'flagged') {
    return (
      <Badge tone="warning" icon={<Flag className="size-3" aria-hidden />}>
        flagged
      </Badge>
    );
  }
  return <Badge icon={<HelpCircle className="size-3" aria-hidden />}>unverified</Badge>;
}
