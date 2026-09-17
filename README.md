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
addons/gateway/shared-gateway/  # Gateway 매니페스트(컨트롤러는 AKS 관리형이라 GatewayClass도 없다)
addons/karpenter/nodepool/      # NAP의 NodePool/AKSNodeClass CR 매니페스트
addons/kyverno/custom-policies/ # 이 저장소가 소유하는 ClusterPolicy 매니페스트
addons/catalog/   # opt-in 카탈로그(cluster Secret 라벨로 옵트인) - karpenter.yaml
scripts/          # 주석 규칙 검사기(.py다 - 아래 "로컬 게이트" 절 참고)
.githooks/        # pre-commit 훅
```

## root App이 읽는 범위 — `include` allow-list

`bootstrap/root-app.yaml`은 `directory.include`에 적힌 경로만 매니페스트로 읽는다. 지금은
`projects/`·`clusters/**/cluster-secret.yaml`·`addons/baseline/`·`addons/catalog/`·`bootstrap/`의
두 Application 파일이다. **그 밖은 무엇이든 무시한다** — `addons/<addon>/<dir>/`의 CR
매니페스트(전담 ApplicationSet이 따로 읽는다), helm values(`bootstrap/argocd-values.yaml`), 도구
파일 전부.

이 저장소는 `exclude`와 `+argocd:skip-file-rendering` 마커를 쓰지 않는다. 기각 근거는
`iac-module-library`의 `docs/architectures/gitops-hub-spoke/gitops.md` 「하지 않는 것」이 갖는다.

매니페스트 디렉토리를 새로 만들면 `include`에 한 줄 더한다. 이미 있는 디렉토리 안에서 파일이
늘고 주는 것은 `root-app.yaml`과 무관하다. ⚠️ **렌더가 깨지는 파일이 든 경로**를 `include`에
넣으면 그 spec이 적용된 뒤부터 자기 갱신이 멈춘다. root App은 자기 spec을 클러스터에 적용된
옛 spec으로 렌더한 뒤에야 갱신하는데, 그 렌더가 깨지면 갱신에 이르지 못한다. 그 파일을 고치는
커밋이 풀거나, `argocd-seed.sh --from 5 --to 5`로 커밋본 `root-app.yaml`을 손으로 다시 apply한다.

`addons/<addon>/<dir>/`는 값을 주입할 일이 없으면 평문 매니페스트 디렉토리다. 이 저장소의
셋(`gateway/shared-gateway`·`karpenter/nodepool`·`kyverno/custom-policies`)이 전부 그렇다.
AWS 원본은 EC2NodeClass·GatewayClass가 per-cluster 값을 받아 helm 차트인 것이 있다.

## 로컬 게이트 — 이 저장소의 유일한 강제 지점

이 저장소에는 CI가 없다. ArgoCD가 `main`을 pull로 reconcile할 뿐이라 **커밋 전 훅이
아니면 아무것도 막지 못한다.** clone마다 한 번 켠다.

```bash
git config core.hooksPath .githooks
brew install shellcheck        # 셸 게이트가 요구한다. 없으면 훅이 즉시 실패한다
```

`.githooks/pre-commit`이 staged 파일 중 `addons/`·`projects/`·`clusters/`·`bootstrap/`의
`.yaml`/`.sh`, 저장소 `.md`, `scripts/*.py`, `.githooks/*`를 골라
`scripts/validate-comment-conventions.py`에 넘긴다. 검사기는 주석에 **외부 참조**(문서 절
번호·결정 식별자)와 **이력 서술**(날짜·세션 번호, 그리고 측정을 사건으로 적은 서술)이 있는지만
본다 — 외부 참조는 가리키는 쪽이 움직이면 조용히 틀려지고, 이력 서술은 언제 누가 왜 바꿨는지를
`git blame`과 커밋 메시지가 이미 답한다. 정확한 패턴 목록은 검사기 자신이 갖는다. 규칙 자체의 SSOT는 `iac-module-library`의
`docs/conventions.md`와 `docs/writing-style.md`이고, 검사기는 규칙 텍스트를 다시 쓰지 않는다.

전체를 한 번에 돌리려면 저장소 루트에서:

```bash
python3 scripts/validate-comment-conventions.py
```

staged된 `.sh`에는 `bash -n`(문법)과 `shellcheck -x`(인용·확장·종료코드)가 함께 돈다.
`bootstrap/argocd-seed.sh`는 workbench에서 사람이 손으로 돌리는 스크립트라, 깨진 채 머지되면
부트스트랩 한가운데서 드러난다.

⛔ 매니페스트 렌더 결과는 검사하지 않는다. 그것은 ArgoCD가 sync 시점에 판정하고,
훅에서 흉내 내면 두 판정이 갈린다.

의도적 우회는 `git commit --no-verify`이고, 사유를 커밋 메시지에 남긴다.

`eks-platform-gitops`가 같은 게이트를 같은 내용으로 갖는다. 한쪽을 고치면 다른 쪽도 함께
고친다 — 드리프트를 검사하는 장치는 없다.

seed 절차(workbench 준비 · GitHub App 설치 범위 · `argocd-seed.sh` 실행 순서)는
`aks-reference-infra`의 `docs/hub-lifecycle.md` 「GitOps 씨딩」이 소유한다.
