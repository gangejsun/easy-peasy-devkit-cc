<!-- epcc-pack: frontend/react-vite v3.12.0 -->
# Component Patterns

React 18 + TypeScript SPA에서 컴포넌트를 어디에 두고, 언제 공통으로 올리고,
무엇을 소유하게 할지에 대한 규칙.

## 1. 세 가지 층위

| 층위 | 위치 | 아는 것 | 모르는 것 |
| --- | --- | --- | --- |
| Page | `features/<f>/pages/` | 라우트 파라미터, 쿼리 훅, 레이아웃 조립 | 세부 마크업 |
| Feature component | `features/<f>/components/` | 이 기능의 도메인 타입 | 다른 기능, 라우팅 |
| Common component | `components/common/`, `components/layout/` | 시각적 계약(props)만 | 도메인, 페칭, 라우팅 |

규칙: **의존은 아래로만 흐른다.** 공통 컴포넌트는 `features/`를 import하지 않는다.
이 방향이 깨지면 공통 컴포넌트가 특정 기능에 묶여 재사용이 끝난다.

## 2. 새로 만들기 전에 검색한다 (탐색 의무)

중복 컴포넌트의 대부분은 "추출하지 않아서"가 아니라 **"있는 줄 몰라서"** 생긴다.
공통 후보를 만들기 전에 최소 두 가지 축으로 검색한다.

```bash
# ① 이름 축 — 하려는 역할의 흔한 이름들
rg -il "pageshell|emptystate|datatable|modal|drawer|badge" src/components src/features

# ② 마크업 축 — 이미 쓰고 있는 클래스 조합
rg -l "rounded-lg border .* bg-white" src/components

# ③ 공통 디렉토리 목록 훑기 (30초면 끝난다)
ls src/components/common src/components/layout
```

검색해서 **비슷하지만 부족한** 것을 찾았다면, 새로 만들지 말고 props를 하나 늘린다.
새 파일은 기존 것을 확장할 수 없다고 판단했을 때에만 만들고, 그 판단 근거를 PR에 적는다.

## 3. 추출 시점

- 같은 마크업 덩어리가 **세 번째** 등장하면 추출한다 (두 번은 우연, 세 번은 패턴)
- 두 개 **이상의 기능**이 같은 UI를 쓰면 두 번째에 바로 `components/common/`으로 올린다
- 한 기능 안에서만 반복되면 `features/<f>/components/`에 둔다 — 성급한 공통화는
  props가 폭발한 "만능 컴포넌트"를 만든다
- 추출 대상은 **마크업과 스타일**이다. 데이터 페칭·라우팅은 함께 올리지 않는다

```tsx
// ✅ 공통 셸은 슬롯만 갖는다
export function PageShell({ title, actions, children }: PageShellProps) {
  return (
    <div className="mx-auto w-full max-w-5xl px-6 py-8">
      <header className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-slate-900">{title}</h1>
        {actions}
      </header>
      {children}
    </div>
  );
}

// ❌ 공통 셸이 도메인을 안다 — 다음 기능에서 재사용 불가
export function PageShell({ taskId }: { taskId: string }) {
  const { data } = useTaskQuery(taskId);           // 페칭
  const navigate = useNavigate();                   // 라우팅
  return <div>{data?.title}<button onClick={() => navigate('/tasks')} /></div>;
}
```

## 4. 디자인 토큰 소유권

공통 컴포넌트가 자기 **높이·타이포·여백·모서리**를 단독으로 정의한다. 사용처는
`variant`/`size` props로만 고른다. 사용처가 `className`으로 토큰을 덮어쓰기 시작하면
"공통"이라는 말이 거짓이 되고, 디자인 변경이 전수 수정으로 번진다.

```tsx
// ✅ 토큰은 컴포넌트 안 한 곳에서만 정의된다
const sizes = {
  sm: 'h-8 px-3 text-xs',
  md: 'h-10 px-4 text-sm',
  lg: 'h-12 px-6 text-base',
} as const;

export function Button({ size = 'md', variant = 'primary', className, ...rest }: ButtonProps) {
  return <button className={cn(base, sizes[size], variants[variant], className)} {...rest} />;
}

// ❌ 사용처가 토큰을 덮어쓴다 — size prop이 무의미해지고 규격이 흩어진다
<Button className="h-9 px-5 text-[13px] rounded-none" />
```

`className`은 **위치성 조정**(`mt-4`, `w-full`, `col-span-2`)까지만 허용한다.
`tailwind-merge` 기반 `cn()`을 쓰면 뒤에 온 클래스가 이기므로, 이 구분은 문서화된
합의로만 지켜진다 — 코드 리뷰에서 잡는다.

## 5. Props 설계

```tsx
// ✅ 상태를 boolean 여러 개로 쪼개지 않고 union으로 모은다
type Status = 'idle' | 'loading' | 'success' | 'error';
type Props = { status: Status };

// ❌ 조합 불가능한 상태가 표현된다 (isLoading && isError가 가능해진다)
type Props = { isLoading: boolean; isError: boolean; isSuccess: boolean };
```

- 네이티브 요소를 감싸면 `ComponentPropsWithoutRef<'button'>`을 확장해 `aria-*`,
  `type`, `onClick`을 자동으로 받게 한다
- 콜백은 `onXxx` 명명, 값은 `value`/`defaultValue` 관례를 따른다
- 하위에 무엇이 올지 컴포넌트가 결정하지 않아도 되면 `ReactNode` 슬롯을 쓴다
  (`actions`, `footer`, `icon`) — props로 문자열·아이콘 이름을 받는 것보다 확장성이 높다
- 옵션이 5개를 넘고 서로 배타적이면 컴포넌트를 쪼갠다

## 6. 파생 상태는 렌더 중에 계산한다

`useState` + `useEffect`로 props에서 값을 파생시키면 한 프레임 늦은 값이 렌더되고,
React 18 StrictMode(개발)에서 effect가 두 번 실행되어 증상이 불규칙해진다.

```tsx
// ✅ 렌더 중 계산 (비싸면 useMemo)
const visible = useMemo(() => tasks.filter((t) => t.status !== 'done'), [tasks]);

// ❌ effect로 상태를 동기화 — 렌더 한 번 밀리고 소스가 둘이 된다
const [visible, setVisible] = useState<Task[]>([]);
useEffect(() => { setVisible(tasks.filter((t) => t.status !== 'done')); }, [tasks]);
```

## 7. 리스트와 key

```tsx
// ✅ 서버가 준 안정적인 식별자
{tasks.map((t) => <TaskCard key={t.id} task={t} />)}

// ❌ 인덱스 key — 정렬·삭제·낙관적 삽입에서 입력 상태가 잘못된 행에 붙는다
{tasks.map((t, i) => <TaskCard key={i} task={t} />)}
```

## 8. 최적화는 측정 후에

`memo`/`useMemo`/`useCallback`은 비교 비용과 메모리를 쓴다. 기본은 쓰지 않는 것이고,
React DevTools Profiler로 실제 리렌더 비용을 확인한 뒤에 붙인다. 다만 다음 두 경우는
측정 없이 붙여도 좋다: ① `memo`된 자식에 넘기는 콜백/객체, ② 수백 행 이상의 리스트 항목.

## 9. 합성으로 확장한다 (props 폭발 대신 슬롯)

옵션이 늘어날 때 props를 계속 추가하면 컴포넌트가 모든 사용처의 요구를 흡수한다.
자리(slot)를 열어 주면 컴포넌트는 **레이아웃과 토큰**만 소유하고, 내용은 호출부가 정한다.

```tsx
// components/common/Field.tsx — 라벨·에러·설명의 배치와 접근성 연결을 소유한다
type FieldProps = {
  label: string;
  htmlFor: string;
  error?: string;
  hint?: string;
  children: ReactNode;   // 입력 요소는 호출부가 넣는다
};

export function Field({ label, htmlFor, error, hint, children }: FieldProps) {
  const hintId = hint ? `${htmlFor}-hint` : undefined;
  const errorId = error ? `${htmlFor}-error` : undefined;
  return (
    <div className="space-y-1.5">
      <label htmlFor={htmlFor} className="block text-sm font-medium text-slate-700">
        {label}
      </label>
      <div aria-describedby={cn(hintId, errorId)}>{children}</div>
      {hint && !error && <p id={hintId} className="text-xs text-slate-500">{hint}</p>}
      {error && <p id={errorId} role="alert" className="text-xs text-danger-600">{error}</p>}
    </div>
  );
}
```

```tsx
// 호출부 — 입력 종류가 늘어나도 Field는 바뀌지 않는다
<Field label="제목" htmlFor="title" error={fieldErrors.title?.[0]} hint="2자 이상">
  <input id="title" className="h-10 w-full rounded-md border px-3 text-sm" />
</Field>

<Field label="담당자" htmlFor="assignee">
  <select id="assignee" className="h-10 w-full rounded-md border px-3 text-sm">…</select>
</Field>
```

```tsx
// ❌ 입력 종류마다 props가 늘어난다 — 다음 요구가 오면 또 늘어난다
<Field label="담당자" type="select" options={users} multiple searchable
       renderOption={...} inputProps={{...}} selectProps={{...}} />
```

같은 원리를 목록에도 적용한다. 헤더·본문·빈 상태를 슬롯으로 받으면 하나의 `DataTable`이
모든 기능에서 쓰인다 — 컬럼 정의만 호출부가 넘긴다.

```tsx
type Column<T> = { key: string; header: ReactNode; cell: (row: T) => ReactNode; className?: string };

export function DataTable<T extends { id: string }>({ rows, columns, empty }: {
  rows: T[]; columns: Column<T>[]; empty?: ReactNode;
}) {
  if (rows.length === 0) return <>{empty}</>;
  return (
    <table className="w-full text-sm">
      <thead>
        <tr className="border-b border-surface-border text-left text-xs text-slate-500">
          {columns.map((c) => <th key={c.key} className={cn('py-2', c.className)}>{c.header}</th>)}
        </tr>
      </thead>
      <tbody>
        {rows.map((row) => (
          <tr key={row.id} className="border-b border-surface-border last:border-0">
            {columns.map((c) => <td key={c.key} className={cn('py-3', c.className)}>{c.cell(row)}</td>)}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
```

제네릭 `T extends { id: string }`이 key 규칙을 타입으로 강제한다 — 인덱스 key가 들어올 자리가 없다.

## 오용 목록 — 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `React.memo` vs `useMemo` | `memo`는 **컴포넌트**를 props 얕은 비교로 건너뛴다. `useMemo`는 **값**을 캐시한다. 리스트 항목 렌더가 무거우면 `memo`, 계산이 무거우면 `useMemo` |
| `useEffect` vs 렌더 중 계산 | effect는 **외부 시스템과의 동기화**(구독, 타이머, DOM 측정)에만. props/state에서 나오는 값은 렌더 중에 계산 |
| `useEffect` vs `useLayoutEffect` | 화면에 그려지기 전에 DOM을 측정·보정해야 할 때만 `useLayoutEffect`. 그 외에는 `useEffect` (레이아웃 이펙트는 페인트를 막는다) |
| StrictMode 이중 실행 vs 진짜 버그 | React 18 개발 모드는 effect를 마운트→언마운트→마운트로 두 번 돌린다. 정리(cleanup)를 제대로 쓰면 해결된다. `useRef` 가드로 두 번째 실행을 막는 것은 증상 은폐다 |
| `key={index}` vs `key={item.id}` | 목록이 절대 재정렬·삽입·삭제되지 않는 정적 배열에서만 인덱스 허용. 서버 목록은 항상 `id` |
| 공통 컴포넌트에 훅 주입 vs props 주입 | 공통 컴포넌트가 `useQuery`/`useNavigate`를 부르는 순간 그 컴포넌트는 특정 기능 전용이 된다. 필요한 값과 콜백은 props로 받는다 |
| `forwardRef` 필요 vs 불필요 | React 18에서는 ref가 props로 전달되지 않는다. DOM 노드를 밖에서 만져야 하는 공통 입력·버튼은 `forwardRef` 필수 |
| 컴포넌트 분리 vs 파일 분리 | 한 파일에 여러 컴포넌트를 두는 것은 괜찮다. 기준은 파일 수가 아니라 **재사용 범위**다 — 밖에서 쓰지 않는 하위 컴포넌트는 같은 파일에 둔다 |
