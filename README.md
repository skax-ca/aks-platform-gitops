# aks-platform-gitops

**읽는 사람**: 이 저장소의 매니페스트를 고치거나, 클러스터·addon을 새로 등록하는 사람.

**오너**: GitHub org [`skax-ca`](https://github.com/skax-ca) 소속. 클러스터·IAM 문의는
`aks-reference-infra` 쪽과 겹칠 수 있다.

**플랫폼 GitOps monorepo(계층 2)** - ArgoCD가 pull로 reconcile하는 플랫폼 소관
매니페스트 저장소. AWS 원본 [`eks-platform-gitops`](https://github.com/skax-ca/eks-platform-gitops)의
Azure 대응.

⛔ **설계 SSOT는 이 저장소가 아니다.** 규약을 바꾸려면 [`skax-ca/iac-module-library`의 `docs/`](https://github.com/skax-ca/iac-module-library/tree/main/docs)를 먼저 고친다. 문서 목록은 [`docs/README.md`](https://github.com/skax-ca/iac-module-library/blob/main/docs/README.md)가 소유한다. Azure에서 갈리는 판단(GitOps 엔진, L7 Ingress로 App Routing을 쓰고 AGFC·Envoy Gateway를 쓰지 않는 이유)은 [`docs/architectures/gitops-hub-spoke/azure/README.md`](https://github.com/skax-ca/iac-module-library/blob/main/docs/architectures/gitops-hub-spoke/azure/README.md)가 갖는다. 클러스터·네트워킹·bootstrap 자격증명은 `aks-reference-infra`가 SSOT다.

---

## AWS 원본과 갈리는 것

매니페스트 대부분은 AWS 원본과 같다. 이 저장소에서 달라지는 것은 아래 둘이다.

| 갈림점 | AWS 원본 | 이 저장소(Azure) |
|---|---|---|
| L7 Ingress | aws-load-balancer-controller(helm, baseline) | AKS App Routing(Gateway API/Istio, AKS 관리형). 컨트롤러·CRD·GatewayClass는 `aks-reference-infra`의 `live/hub/aks`가 `ingressProfile`을 켜면 클러스터 안에 나타나고, 이 저장소는 `Gateway` CR 하나만 얹는다. 내부 LB는 `Gateway.spec.infrastructure.annotations`의 AKS Service annotation 하나다 |
| addon 배포 원칙 | Terraform=IAM만, 컨트롤러=Helm, CR=GitOps | App Routing만 컨트롤러 단계가 Helm이 아니라 Terraform이다. Karpenter·Kyverno는 원칙 그대로다 |

## 이 저장소가 다루는 것 / 다루지 않는 것

AWS 원본과 동일한 3계층 소유 모델에서 **계층 2만** 담당한다.

| 계층 | 무엇 | 어디 |
|---|---|---|
| 1. Terraform | 클러스터·네트워킹·IAM(Managed Identity·role assignment) | `skax-ca/aks-reference-infra` |
| **2. 플랫폼 GitOps** | **helm addon · 클러스터 등록 · AppProject 가드레일** | **이 저장소** |
| 3. 앱 GitOps | 비즈니스 워크로드 | 앱팀별 repo(범위 밖) |

⛔ **`apps/` 디렉토리는 의도적으로 없다.** 플랫폼 addon 업그레이드는 fleet 전체에, 앱 배포는 한
팀에 영향을 준다 — 같은 저장소에 두면 리뷰어·릴리스 주기·blast radius가 섞인다.

## 레이아웃

```
bootstrap/    # App-of-Apps root(자기소멸/self-superseding) + ArgoCD 자기 관리 매니페스트
              #   + argocd-seed.sh(seed 실행 스크립트. 이 저장소가 소유한다)
clusters/hub/aks-demo-hub-krc-main-01/  # cluster Secret
projects/     # AppProject 가드레일 - platform.yaml
applicationsets/baseline/  # 전 클러스터 팬아웃 ApplicationSet(environment 라벨). root App이 읽는다
applicationsets/catalog/   # opt-in 카탈로그 ApplicationSet(cluster Secret 라벨로 옵트인) - karpenter.yaml
addons/<addon>/            # 위 ApplicationSet의 source가 읽는 내용물. root App은 읽지 않는다
addons/gateway/shared-gateway/  #   Gateway 매니페스트(컨트롤러는 AKS 관리형이라 GatewayClass도 없다)
addons/karpenter/nodepool/      #   NAP의 NodePool/AKSNodeClass CR 매니페스트
addons/kyverno/custom-policies/ #   이 저장소가 소유하는 ClusterPolicy 매니페스트
scripts/          # 주석 규칙 검사기(.py다 - 아래 "로컬 게이트" 절 참고)
.githooks/        # pre-commit 훅
```

## root App이 읽는 범위 — `include` allow-list

`bootstrap/root-app.yaml`은 `directory.include`에 적힌 경로만 매니페스트로 읽는다. 지금은
`projects/`·`clusters/**/cluster-secret.yaml`·`applicationsets/**`·`bootstrap/`의 두 Application
파일이다. **그 밖은 무엇이든 무시한다** — `addons/` 전체(CR 매니페스트는 전담 ApplicationSet이
따로 읽는다), helm values(`bootstrap/argocd-values.yaml`), 도구 파일 전부.

이 저장소는 `exclude`와 `+argocd:skip-file-rendering` 마커를 쓰지 않는다. 기각 근거는
`iac-module-library`의 `docs/architectures/gitops-hub-spoke/gitops.md` 「하지 않는 것」이 갖는다.

매니페스트 디렉토리를 새로 만들면 `include`에 한 줄 더한다. `applicationsets/` 아래는 하위
디렉토리까지 전부 읽으므로(`**`), 그 안에서 파일이 늘고 주는 것은 `root-app.yaml`과 무관하다. ⚠️ **렌더가 깨지는 파일이 든 경로**를 `include`에
넣으면 그 spec이 적용된 뒤부터 자기 갱신이 멈춘다. root App은 자기 spec을 클러스터에 적용된
옛 spec으로 렌더한 뒤에야 갱신하는데, 그 렌더가 깨지면 갱신에 이르지 못한다. 그 파일을 고치는
커밋이 풀거나, `argocd-seed.sh --from 5 --to 5`로 커밋본 `root-app.yaml`을 손으로 다시 apply한다.

`addons/<addon>/<dir>/`는 값을 주입할 일이 없으면 평문 매니페스트 디렉토리다. 이 저장소의
셋(`gateway/shared-gateway`·`karpenter/nodepool`·`kyverno/custom-policies`)이 전부 그렇다.
per-cluster 값을 CR에 넣어야 하면 helm 차트여야 한다 — ApplicationSet의 fasttemplate은
Application spec에만 적용되고 git 경로 안의 파일에는 적용되지 않기 때문이다.

## ApplicationSet 공통 규약

매니페스트마다 반복하지 않고 여기 한 번 적는다. 개별 파일 주석은 그 파일에만 참인 것만 갖는다.

| 항목 | 규약 |
|---|---|
| 팬아웃 | cluster generator가 라벨이 맞는 cluster Secret마다 Application을 1개 만든다. ArgoCD 내장 `in-cluster`에는 Secret도 라벨도 없어 걸리지 않는다 — cluster Secret을 명시적으로 만드는 이유다 |
| `finalizers` | `resources-finalizer.argocd.argoproj.io`를 template에 둔다. 없으면 Application CR을 지워도 그것이 만든 리소스가 클러스터에 orphan으로 남는다 |
| cluster-scoped CR | NodePool·AKSNodeClass·ClusterPolicy는 cluster-scoped라 `destination.namespace`가 형식상 값이다 |

⚠️ **돌고 있는 클러스터가 있을 때 ApplicationSet 이름을 바꾸지 않는다.** 이름이 바뀌면 삭제로
처리되고, 그것이 만든 Application이 `ownerReference`를 따라 지워지면서 finalizer가 **실물까지
prune한다.** 정리할 수 있는 시점은 전면 철거 이후 seed 이전뿐이다.

### staged 전파 — `-prd` · `-nonprd` 두 블록

한 파일 안에 티어별 ApplicationSet 두 개를 둔다. 승격할 때 두 `targetRevision`을 나란히 읽어야
하기 때문이고, 그 차이가 승격이 어디까지 갔는지를 저장소에 기록한다. 다르면 진행 중, 같으면 끝난
것이다.

**이 저장소에서 staged는 Kyverno뿐이다.** 노드와 트래픽을 다루는 컨트롤러를 전부 관리형으로
받으므로(NAP·App Routing) 버전 핀을 가진 것이 엔진과 PSS 정책 둘뿐이다.

⛔ **두 블록을 함께 고친다.** 갈려도 되는 값은 `targetRevision` 하나다.

⚠️ 그 티어의 클러스터가 없으면 대상이 0개가 된다. 사고가 아니라 **빈 슬롯**이고, cluster Secret이
그 `tier`로 등록되는 순간 팬아웃된다. ArgoCD는 대상 0개를 오류로 보고하지 않으므로, 0이 의도인지
사고인지는 등록된 cluster Secret의 `tier` 값을 세어 구분한다.

## cluster Secret 라벨 계약

ApplicationSet이 읽는 라벨이다. 빠지면 그 addon만 조용히 안 뜬다.

| 라벨 | 읽는 쪽 | 값 |
|---|---|---|
| `environment` | baseline 팬아웃 전체 | `hub` · `dev` 등. 존재 자체가 매칭 조건이다 |
| `tier` | Kyverno의 `-prd`/`-nonprd` 선택 | `prd` \| `nonprd` |
| `addon-karpenter: enabled` | NodePool/AKSNodeClass 구독 | NAP을 켠 클러스터만 |

⚠️ **teardown은 매칭 라벨을 먼저 뗀 뒤 Secret을 지운다.** git 이력의 마지막 cluster-secret을 그대로
되살리면 라벨이 빠진 껍데기이고, 그 상태로는 Application이 하나도 생기지 않는다.

## 로컬 게이트 — 이 저장소의 유일한 강제 지점

이 저장소에는 CI가 없다. ArgoCD가 `main`을 pull로 reconcile할 뿐이라 **커밋 전 훅이
아니면 아무것도 막지 못한다.** clone마다 한 번 켠다.

```bash
git config core.hooksPath .githooks
brew install shellcheck        # 셸 게이트가 요구한다. 없으면 훅이 즉시 실패한다
```

`.githooks/pre-commit`이 staged 파일 중 `applicationsets/`·`addons/`·`projects/`·`clusters/`·`bootstrap/`의
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
