# aks-platform-gitops

**읽는 사람**: 이 저장소의 매니페스트를 고치거나, 클러스터·addon을 새로 등록하는 사람.

**오너**: GitHub org [`skax-ca`](https://github.com/skax-ca) 소속. 클러스터·IAM 문의는
`aks-reference-infra` 쪽과 겹칠 수 있다.

**플랫폼 GitOps monorepo(계층 2)** - ArgoCD가 pull로 reconcile하는 플랫폼 소관
매니페스트 저장소. AWS 원본 [`eks-platform-gitops`](https://github.com/skax-ca/eks-platform-gitops)의
Azure 대응.

⛔ **설계 SSOT는 이 저장소가 아니다.** 클러스터·네트워킹·bootstrap 자격증명은
`aks-reference-infra` 자체가 SSOT다. GitOps 엔진·Ingress addon 선정 같은 이
저장소 고유의 설계 판단은 아래 표와 이 저장소 자신의 매니페스트 주석이 SSOT다.

✅ **hub 클러스터에 배포 완료.** self-managed ArgoCD가 자기 자신을 포함해
Synced/Healthy 상태다. 아래 「다음 단계」에 적힌 이월 항목은 이 파일 갱신 시점에
전부 재확인한 것은 아니다. 실제 상태는 `argocd app list --core` 등으로 직접 조회한다.

---

## 확정된 설계

| 갈림점 | AWS 원본 | 이 저장소(Azure) |
|---|---|---|
| GitOps 엔진 | self-managed ArgoCD | **self-managed ArgoCD**(관리형 확장은 Public Preview라 보류) |
| L7 Ingress(ALBC 대응) | aws-load-balancer-controller(helm, baseline) | **AKS App Routing(Gateway API/Istio 기반, 관리형)**. AGFC(Application Gateway for Containers)는 frontend가 공인 FQDN만 지원해(private/internal 옵션 없음, Microsoft 공식 문서로 확정) 이 저장소의 "hub는 전부 private" 원칙과 부딪혀 쓰지 않는다. App Routing은 AKS가 컨트롤러·CRD·GatewayClass를 전부 관리(패치·마이너 업그레이드까지 AKS 클러스터 업그레이드에 맞춰 자동)하는 GA 경로다 — "AKS는 관리형 서비스를 적극 지원·활용한다"는 기조에 따라 자체 설치형(Envoy Gateway 등) 대신 이쪽을 택했다. 내부 LB는 `Gateway.spec.infrastructure.annotations`의 표준 AKS Service annotation 하나로 끝난다(경위는 `addons/baseline/gateway.yaml` 헤더 참조) |
| addon 배포 원칙 | Terraform=IAM만, 컨트롤러=Helm, CR=GitOps | App Routing은 컨트롤러가 100% AKS 관리형(Helm 없음) — Terraform은 `aks-reference-infra`의 `live/hub/aks`가 `azapi_update_resource`로 `ingressProfile`을 켜는 것뿐이고, GitOps는 `Gateway` CR 하나만 얹는다. Karpenter·Kyverno는 원칙 그대로 유지 |

## 이 저장소가 다루는 것 / 다루지 않는 것

AWS 원본과 동일한 3계층 소유 모델에서 **계층 2만** 담당한다.

| 계층 | 무엇 | 어디 |
|---|---|---|
| 1. Terraform | 클러스터·네트워킹·IAM(Managed Identity·role assignment) | `skax-ca/aks-reference-infra` |
| **2. 플랫폼 GitOps** | **helm addon · 클러스터 등록 · AppProject 가드레일** | **이 저장소** |
| 3. 앱 GitOps | 비즈니스 워크로드 | 앱팀별 repo(범위 밖) |

⛔ **`apps/` 디렉토리는 의도적으로 없다** - AWS 원본과 같은 이유(플랫폼 addon
업그레이드는 fleet 전체에, 앱 배포는 한 팀에만 영향을 준다).

## 레이아웃

```
bootstrap/    # App-of-Apps root(자기소멸/self-superseding) + ArgoCD 자기 관리 매니페스트
              #   + argocd-seed.sh(seed 실행 스크립트. 이 저장소가 소유한다)
clusters/hub/aks-demo-hub-krc-main-01/  # cluster Secret(라벨에 못 담는 값이 생기면 values.yaml도)
projects/     # AppProject 가드레일 - platform.yaml
addons/baseline/  # 전 클러스터 팬아웃 ApplicationSet(environment 라벨) - gateway.yaml 등
addons/gateway/shared-gateway/  # Gateway 로컬 helm 차트(컨트롤러는 AKS 관리형이라 GatewayClass도
                                #   없다 - per-cluster 값은 없지만 마커 메커니즘 때문에 helm이다,
                                #   아래 "root App 스캔에서 파일을 빼는 방법" 절 참고)
addons/karpenter/nodepool/      # NAP의 NodePool/AKSNodeClass CR 로컬 helm 차트
addons/kyverno/custom-policies/ # 이 저장소가 소유하는 ClusterPolicy 로컬 helm 차트
addons/catalog/   # opt-in 카탈로그(cluster Secret 라벨로 옵트인) - karpenter.yaml
scripts/          # 주석 규칙 검사기(.py다 - 아래 "로컬 게이트" 절 참고)
.githooks/        # pre-commit 훅
```

## root App 스캔에서 파일을 빼는 방법 — 마커, `exclude` 아님

`bootstrap/root-app.yaml`은 저장소 루트를 재귀로 스캔해 모든 `.yaml`/`.yml`/`.json`을
매니페스트로 적용한다. `addons/karpenter/nodepool/`의 helm 템플릿(`{{ .Values.environment }}`
등 미치환 문법)처럼 **매니페스트가 아닌 파일**은 스캔에서 빠져야 한다.

⛔ **`root-app.yaml`의 `exclude` 목록을 늘리지 않는다.** 대신 파일 안에
`+argocd:skip-file-rendering` 마커를 넣는다(AWS 원본 `eks-platform-gitops`와 동일 규약).

- 평문 YAML(`Chart.yaml`): `# +argocd:skip-file-rendering`
- helm 템플릿: `{{- /* +argocd:skip-file-rendering … */ -}}`(파일 내용에는 남고 렌더
  출력에는 안 남는다)

🔴 **마커의 함정 — 마커를 설명하는 주석도 마커다.** 판정은 파일 전체의 단순 문자열 포함
검사라, 주석이든 문서든 그 문자열이 한 번이라도 나타나면 파일 전체가 스캔에서 빠진다.
`root-app.yaml` 자신의 주석에 마커 문자열을 그대로 적으면 **root-app이 자기 자신을
스캔에서 제외**한다 — 에러 없이 조용히, 영구 `OutOfSync`로만 드러난다.

⚠️ **마커는 root-app만 빼는 게 아니라 "Directory 타입으로 이 파일을 읽는 모든
Application"에서 뺀다 — 전담 Application 자기 자신도 예외가 아니다.** 마커가 붙은
평문 `gateway.yaml` 하나를 `addons/gateway/shared-gateway/`에 두고 그 경로를
`addons/baseline/gateway.yaml`의 전담 ApplicationSet이 **Directory 소스**로 읽으면,
그 ApplicationSet 자신도 마커에 걸려 렌더링이 통째로 빈다 — `argocd app manifests`가
빈 출력을 반환하는데 `Application`은 리소스 0개라 비교할 게 없으니 `Synced`/`Healthy`로
조용히 표시된다(에러도 경고도 없다). `Chart.yaml`이 있는 디렉토리를 전담 소스로
참조하면 Helm 타입으로 인식돼 이 함정을 피한다(`addons/karpenter/nodepool/`·
`addons/gateway/shared-gateway/`가 이 형태) — **마커가 붙은 파일을 실제로 렌더해야
하는 전담 Application이 있다면, 그 소스는 반드시 Helm 타입이어야 한다.** 평문
Directory 소스로 그 파일 자체를 노출하는 조합은 성립하지 않는다.

**`argocd-seed.sh`는 `.sh`라 애초에 directory 소스의 스캔 대상이 아니다.**

## 로컬 게이트 — 이 저장소의 유일한 강제 지점

이 저장소에는 CI가 없다. ArgoCD가 `main`을 pull로 reconcile할 뿐이라 **커밋 전 훅이
아니면 아무것도 막지 못한다.** clone마다 한 번 켠다.

```bash
git config core.hooksPath .githooks
brew install shellcheck        # 셸 게이트가 요구한다. 없으면 훅이 즉시 실패한다
```

`.githooks/pre-commit`이 staged 파일 중 `addons/`·`projects/`·`clusters/`·`bootstrap/`의
`.yaml`/`.sh`, 저장소 `.md`, `scripts/*.py`, `.githooks/*`를 골라
`scripts/validate-comment-conventions.py`에 넘긴다. 검사기는 주석에 **좌표**(날짜·문서 절
번호·결정 식별자·세션 번호, 그리고 측정을 사건으로 적은 서술)가 있는지만 본다 — 언제 누가
왜 바꿨는지는 `git blame`과 커밋 메시지가 답한다. 정확한 패턴 목록은 검사기 자신이 갖는다. 규칙 자체의 SSOT는 `iac-module-library`의
`docs/conventions.md`와 `docs/writing-style.md`이고, 검사기는 규칙 텍스트를 다시 쓰지 않는다.

전체를 한 번에 돌리려면 저장소 루트에서:

```bash
python3 scripts/validate-comment-conventions.py
```

⚠️ 검사기와 훅이 `.py`와 확장자 없는 파일인 것은 우연이 아니다. `bootstrap/root-app.yaml`의
root App이 `path: .` + `recurse: true`라 **저장소 어디에 두든 `.yaml`은 매니페스트로
흡수된다** — 도구를 `.yaml`로 만들면 그 자체가 클러스터에 실린다.

staged된 `.sh`에는 `bash -n`(문법)과 `shellcheck -x`(인용·확장·종료코드)가 함께 돈다.
`bootstrap/argocd-seed.sh`는 workbench에서 사람이 손으로 돌리는 스크립트라, 깨진 채 머지되면
부트스트랩 한가운데서 드러난다.

⛔ 매니페스트 렌더 결과는 검사하지 않는다. 그것은 ArgoCD가 sync 시점에 판정하고,
훅에서 흉내 내면 두 판정이 갈린다.

의도적 우회는 `git commit --no-verify`이고, 사유를 커밋 메시지에 남긴다.

`eks-platform-gitops`가 같은 게이트를 같은 내용으로 갖는다. 한쪽을 고치면 다른 쪽도 함께
고친다 — 드리프트를 검사하는 장치는 없다.

## 알려진 미해결 항목

- **GitHub App 설치 범위**: repository Secret은 기존 `skax-ca-gitops-reader` App(원래
  `eks-platform-gitops`용)을 재사용한다 - 이 저장소를 GitHub App 설치(installation)
  범위에 추가하는 작업이 seed 실행 전 필요.

## 다음 단계

1. `aks-reference-infra`의 `live/hub/workbench`(별도 세션 진행 중) 완료 대기 -
   private cluster에서 `helm install`·`kubectl apply`를 실행할 환경.
2. GitHub App(`skax-ca-gitops-reader`) 설치 범위에 이 저장소 추가.
3. workbench 준비 후 `bootstrap/argocd-seed.sh --dry-run`으로 먼저 확인, 이어서
   `--to 4`(자기 관리 흡수 이전 단계)까지 실행해 `argocd app diff argocd --core`로
   diff를 확인한 뒤에만 `bootstrap/argocd-app.yaml`의 `automated` 블록을 최종
   확정한다(AWS 원본과 동일 순서, 그 파일 자체 주석 참고).
