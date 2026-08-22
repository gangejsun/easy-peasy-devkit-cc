# Loading · Empty · Error States

데이터를 그리는 모든 화면은 최소 세 갈래를 갖는다. 성공 경로만 구현한 화면은 느린
네트워크, 만료된 세션, 빈 계정에서 흰 화면이 된다.

## 1. 세 상태 + 배경 갱신

```tsx
export function Component() {
  const { data, isPending, isError, error, isFetching, refetch } = useTasksQuery(filter);

  if (isPending) return <ListSkeleton rows={5} />;                    // ① 캐시에 데이터 없음
  if (isError) return <ErrorState error={error} onRetry={refetch} />; // ② 실패

  const tasks = data.pages.flatMap((p) => p.items);   // 커서 페이지들을 하나로 편다
  if (tasks.length === 0) return <EmptyState title="아직 작업이 없습니다" action={<CreateTaskButton />} />;

  return (
    <>
      {isFetching && <TopProgressBar />}   {/* ④ 데이터는 있고 배경에서 갱신 중 */}
      <TaskTable rows={tasks} />
    </>
  );
}
```

순서가 중요하다. `isError`를 먼저 보면 재시도 중에도 에러 화면이 남고, 빈 상태를 먼저
보면 로딩 중에 "데이터 없음"이 번쩍인다.

`enabled: false`로 비활성화한 쿼리는 예외다 — 요청이 뜬 적이 없으므로 `isPending`이
영구히 true다. 이 규칙을 그대로 적용하면 스켈레톤이 사라지지 않는다 (§오용 목록 참고).

## 2. 로딩 표현 선택

| 상황 | 표현 |
| --- | --- |
| 첫 진입, 레이아웃을 아는 목록/카드 | 스켈레톤 (레이아웃 시프트가 없다) |
| 첫 진입, 크기를 모르는 영역 | 중앙 스피너 + 최소 높이 확보 |
| 데이터가 이미 있는 재요청 | 상단 얇은 진행바 또는 살짝 흐리게 — 화면을 치우지 않는다 |
| 버튼 클릭 후 뮤테이션 | 버튼 안 스피너 + `disabled` (더블 서브밋 차단) |
| 200ms 안에 끝날 것 | 아무것도 표시하지 않는다 (깜빡임이 더 나쁘다) |

```tsx
// 스켈레톤은 실제 레이아웃과 같은 박스 크기를 갖는다
export const ListSkeleton = ({ rows }: { rows: number }) => (
  <div className="space-y-3" role="status" aria-label="불러오는 중">
    {Array.from({ length: rows }, (_, i) => (
      <div key={i} className="h-16 animate-pulse rounded-card bg-surface-muted" />
    ))}
  </div>
);
```

## 3. 빈 상태와 에러 상태는 공통 컴포넌트 하나씩이다

두 컴포넌트는 `src/components/common/`에 **한 번만** 정의하고 모든 화면이 같은 props로
부른다. 화면마다 다른 모양으로 부르면 시그니처가 갈라져 타입이 먼저 깨진다.

```tsx
// src/components/common/EmptyState.tsx
export type EmptyStateProps = { title?: string; description?: string; action?: ReactNode };

export function EmptyState({ title = '표시할 항목이 없습니다', description, action }: EmptyStateProps) {
  return (
    <div className="rounded-card border border-dashed border-surface-border p-10 text-center">
      <p className="text-sm font-medium text-slate-900">{title}</p>
      {description && <p className="mt-1 text-sm text-slate-500">{description}</p>}
      {action && <div className="mt-4 flex justify-center">{action}</div>}
    </div>
  );
}
```

```tsx
// src/components/common/ErrorState.tsx
export type ErrorStateProps = {
  title?: string;
  message?: string;
  error?: unknown;          // 넘기면 메시지·요청 ID를 여기서 뽑는다
  onRetry?: () => void;     // 없으면 재시도 버튼을 그리지 않는다 (403/404가 그렇다)
};

export function ErrorState({ title = '문제가 발생했습니다', message, error, onRetry }: ErrorStateProps) {
  const requestId = error instanceof ApiError ? error.requestId : undefined;
  return (
    <div role="alert" className="rounded-card border border-surface-border p-10 text-center">
      <p className="text-sm font-medium text-slate-900">{title}</p>
      <p className="mt-1 text-sm text-slate-500">{message ?? toUserMessage(error)}</p>
      {onRetry && (
        <Button variant="secondary" className="mt-4" onClick={onRetry}>다시 시도</Button>
      )}
      {/* 서버 로그와 잇는 유일한 끈 — 사용자가 이 값을 알려주면 요청 하나를 특정할 수 있다 */}
      {requestId && <p className="mt-3 text-xs text-slate-400">요청 ID: {requestId}</p>}
    </div>
  );
}
```

빈 상태는 두 종류이고, 문구가 달라야 한다.

- **아직 없음**: "첫 작업을 만들어 보세요" + 생성 버튼
- **필터 결과 없음**: "조건에 맞는 작업이 없습니다" + 필터 초기화 버튼

## 4. 에러 분류와 처리 — 분기는 `code`로

백엔드는 실패를 `{ error: { code, message, details? }, requestId }`로 보낸다.
**화면은 `code`로 분기한다.** 상태 코드는 같은데 의미가 다른 경우가 있기 때문이다.

| `code` | 상태 | 화면 대응 |
| --- | --- | --- |
| `NETWORK_ERROR` / `TIMEOUT` | — | "연결을 확인해 주세요" + 재시도 버튼 (클라이언트가 만드는 코드) |
| `UNAUTHORIZED` | 401 | 화면이 아니라 **인증 계층**이 처리 (갱신 → 실패 시 로그인) |
| `FORBIDDEN` | 403 | 역할·스코프 부족. "권한이 없습니다" — 재시도 버튼을 주지 않는다 |
| `NOT_FOUND` | 404 | **없는 리소스 또는 남의 리소스**(백엔드가 존재를 누설하지 않으려 둘을 합쳤다). "찾을 수 없거나 접근 권한이 없습니다" + 목록으로 돌아가는 링크 |
| `CONFLICT` | 409 | "다른 사용자가 먼저 수정했습니다" + 새로고침 |
| `VALIDATION_FAILED` | 422 | 토스트가 아니라 **해당 폼 필드 아래**에 `details`의 메시지 |
| `PAYLOAD_TOO_LARGE` | 413 | "내용이 너무 큽니다" — 입력을 줄이도록 안내 |
| `INTERNAL` | 500 | 일반 에러 화면 + 재시도. 서버 원문 메시지를 그대로 노출하지 않는다 |
| (429) | 429 | "잠시 후 다시 시도" — **자동 재시도는 하지 않는다** |

```tsx
export function toUserMessage(error: unknown): string {
  if (error instanceof ApiError) {
    switch (error.code) {
      case 'NETWORK_ERROR':
      case 'TIMEOUT':      return '연결에 실패했습니다. 네트워크를 확인해 주세요.';
      case 'FORBIDDEN':    return '이 작업을 수행할 권한이 없습니다.';
      case 'NOT_FOUND':    return '요청한 항목을 찾을 수 없거나 접근 권한이 없습니다.';
      case 'CONFLICT':     return '다른 곳에서 먼저 변경되었습니다. 새로고침 후 다시 시도하세요.';
      case 'VALIDATION_FAILED': return '입력값을 다시 확인해 주세요.';
      case 'PAYLOAD_TOO_LARGE': return '내용이 너무 큽니다.';
      case 'INTERNAL':     return '서버에 문제가 발생했습니다.';
      default: return error.status === 429
        ? '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.'
        : error.message;
    }
  }
  return '문제가 발생했습니다. 잠시 후 다시 시도해 주세요.';
}
```

**403·404는 재시도 대상이 아니다.** 재시도 버튼을 주면 사용자가 계속 눌러 서버 로그만
더럽힌다 — `ErrorState`에 `onRetry`를 넘기지 않으면 버튼이 사라진다.
**429도 자동 재시도하지 않는다**: `Retry-After`를 존중하는 백오프 없이 다시 던지면 요율
제한을 더 세게 때린다. 쿼리 `retry`에서 4xx 전체를 제외한다 (`data-fetching.md` §5 —
두 파일의 정책은 하나다).

## 5. 폼 검증 에러 (422)

`details`는 **필드 이름 → 메시지 배열**이다. 값이 문자열이 아니라 배열이라는 점을
놓치면 화면에 `[object Object]`가 뜬다.

```tsx
const { mutate, isPending } = useCreateTaskMutation();
const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});   // Record<string, string[]>

const submit = (input: CreateTaskInput) => {
  setFieldErrors({});
  mutate(input, {
    onError: (e) => {
      if (e instanceof ApiError && e.code === 'VALIDATION_FAILED' && e.details) {
        setFieldErrors(e.details);            // 서버가 준 필드별 메시지를 그대로 사용
      } else {
        toast.error(toUserMessage(e));        // sonner
      }
    },
  });
};

<Field label="제목" htmlFor="title" error={fieldErrors.title?.[0]}>…</Field>
```

클라이언트 검증은 **UX 선행 안내**이고, 최종 판정은 서버의 422다. 클라이언트에만 규칙을
두면 API를 직접 호출하는 경로에서 우회되고, 서버에만 두면 왕복이 잦아진다 — 둘 다 둔다.

## 6. 에러 바운더리

렌더 중 던져진 예외를 잡는 마지막 그물이다. 바운더리 컴포넌트는 **`react-error-boundary`**
패키지의 것이고(`fallbackRender`·`onReset`이 그 API다), 세 층위로 둔다.

```tsx
import { ErrorBoundary } from 'react-error-boundary';
import { QueryErrorResetBoundary } from '@tanstack/react-query';

// ① 앱 최상단 — 무엇을 놓쳐도 흰 화면은 막는다 (main.tsx)
// ② 라우트 — createBrowserRouter의 errorElement (routing.md §4)
// ③ 위젯 — 대시보드 카드 하나가 죽어도 나머지는 산다
<ErrorBoundary fallback={<WidgetError />}>
  <RevenueChart />
</ErrorBoundary>
```

쿼리 에러를 바운더리까지 올리려면 그 쿼리에 `throwOnError: true`를 켜고,
`QueryErrorResetBoundary`로 재시도 시 쿼리를 초기화한다.

```tsx
<QueryErrorResetBoundary>
  {({ reset }) => (
    <ErrorBoundary onReset={reset} fallbackRender={({ resetErrorBoundary }) => (
      <ErrorState onRetry={resetErrorBoundary} />
    )}>
      <TaskWidget />
    </ErrorBoundary>
  )}
</QueryErrorResetBoundary>
```

에러 바운더리가 **잡지 못하는 것**: 이벤트 핸들러 내부의 예외, `setTimeout` 콜백,
`mutate()`의 거부. 이들은 각각의 자리에서 잡아야 한다.

## 오용 목록 — 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `isPending` vs `isFetching` | `isPending`은 "보여줄 데이터가 아직 없다" → 화면을 스켈레톤으로 대체. `isFetching`은 "요청이 떠 있다" → 기존 화면 유지 + 얇은 인디케이터 |
| `isPending` vs `isLoading` (v5) | v5의 `isLoading`은 `isPending && isFetching`이다. 첫 로딩 분기에는 `isPending`을 쓴다 |
| `enabled`로 비활성화된 쿼리 | 비활성 쿼리는 `isPending`이 **영구 true**라 스켈레톤이 사라지지 않는다 → `isLoading`(또는 `isPending && isFetching`)으로 분기하거나, 파라미터가 없는 상태를 별도 안내 화면으로 그린다 |
| `isError` vs `error !== null` | 분기는 `isError`로 한다. `error`는 메시지를 꺼낼 때만 |
| 빈 배열 vs `undefined` | `isPending` 분기를 먼저 통과했으면 `data`는 정의되어 있다. `data?.pages ?? []`로 뭉개면 로딩과 빈 상태가 같은 화면이 된다 |
| `error.status` 분기 vs `error.code` 분기 | 문구 선택은 `code`. 404 하나가 "없음"과 "미인가"를 겸하므로 상태 코드만으로는 갈라지지 않는다 |
| 에러 토스트 vs 인라인 에러 | 화면 전체가 못 뜨면 인라인(에러 화면). 사용자가 방금 누른 동작의 실패는 토스트. 필드 검증은 필드 아래 |
| ErrorBoundary vs `isError` 분기 | 예상 가능한 실패(권한 없음, 없는 리소스)는 `isError` 분기. 예상 못 한 렌더 예외만 바운더리 |
| `throwOnError` vs 기본값 | 기본(false)이 표준이다. 여러 쿼리를 한 화면에서 묶어 한 번에 실패 처리하고 싶을 때만 켠다 |
| 401 화면 처리 vs 인증 계층 처리 | 401을 개별 화면에서 처리하지 않는다. 갱신·로그아웃은 HTTP 계층 한 곳의 책임이다 |
| `role="status"` vs `role="alert"` | 로딩 알림은 `status`(공손). 실패 알림은 `alert`(즉시 읽힘) |
