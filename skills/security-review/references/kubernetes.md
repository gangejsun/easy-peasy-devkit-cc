# 컨테이너·클러스터 — OWASP Kubernetes Top 10 (2022)

<!-- 착안: davila7/claude-code-templates `owasp-security` (MIT · Copyright (c) 2025 Daniel (San) Ávila)
     내용 정본: OWASP Kubernetes Top Ten (2022) — K01:2022 ~ K10:2022. -->

**프로젝트가 K8s로 배포될 때만 읽는다.** 매니페스트·Helm 차트·IaC가 저장소에 있으면 대상이다.
컨테이너를 쓰되 K8s가 아니면 K01·K02·K08만 봐도 된다.

| ID | 이름 | 확인할 것 |
| --- | --- | --- |
| **K01:2022** | Insecure Workload Configurations | `runAsNonRoot: true` · `allowPrivilegeEscalation: false` · `readOnlyRootFilesystem: true` · `privileged: false` · capabilities `drop: [ALL]` · hostPath/hostNetwork/hostPID 미사용 |
| **K02:2022** | Supply Chain Vulnerabilities | 이미지 태그가 `latest`가 아니라 **다이제스트 고정**인가. 베이스 이미지 출처와 스캔. 서명 검증 |
| **K03:2022** | Overly Permissive RBAC | `cluster-admin` 바인딩 · 와일드카드(`verbs: ["*"]`·`resources: ["*"]`) · 기본 ServiceAccount 자동 마운트(`automountServiceAccountToken: false`) |
| **K04:2022** | Lack of Centralized Policy Enforcement | 승인 제어(admission)로 위 항목이 **강제**되는가, 아니면 리뷰에만 의존하는가 |
| **K05:2022** | Inadequate Logging and Monitoring | 감사 로그가 켜져 있고 보존되는가. 권한 거부·예외 이벤트에 알림이 있는가 (A09와 같은 축) |
| **K06:2022** | Broken Authentication | 사람·워크로드 인증이 단기 자격증명인가. 정적 토큰·kubeconfig 공유가 없는가 |
| **K07:2022** | Missing Network Segmentation | 기본 거부 NetworkPolicy가 있는가. 네임스페이스 간 통신이 명시적으로 열린 것만인가 |
| **K08:2022** | Secrets Management Failures | Secret이 base64일 뿐 암호화가 아님을 아는가. etcd 저장 시 암호화 · 외부 시크릿 매니저 · 환경변수보다 파일 마운트 · Git에 평문 Secret 없음 |
| **K09:2022** | Misconfigured Cluster Components | kubelet 익명 접근 · etcd 노출 · API 서버 플래그 · 대시보드 노출 |
| **K10:2022** | Outdated Components | 클러스터·노드·CNI·컨트롤러 버전이 지원 범위 안인가 |

**이 하네스와의 접점**: `guides/backend/aws-container`·`gcp-serverless` 축의 IAM 정책 행이
K03과 같은 축을 이미 본다(과도한 권한 부여 금지). 그쪽이 정본이면 여기서 다시 판정하지 않는다.
