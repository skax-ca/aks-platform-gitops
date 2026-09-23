# aks-platform-gitops

**읽는 사람**: 이 저장소의 매니페스트를 고치거나, 클러스터·addon을 새로 등록하는 사람.

**오너**: GitHub org [`skax-ca`](https://github.com/skax-ca) 소속. 클러스터·IAM 문의는
`aks-reference-infra`가 받는다.

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
applicationsets/platform.yaml # 클러스터마다 부모 Application을 만드는 ApplicationSet. root App이 읽는다
addons/platform/           # 부모 차트. 그 클러스터의 addon Application 전부와 wave·버전 표. root App은 읽지 않는다
addons/<addon>/            # addon Application의 source가 읽는 내용물. root App은 읽지 않는다
addons/gateway/shared-gateway/  #   Gateway 매니페스트(컨트롤러는 AKS 관리형이라 GatewayClass도 없다)
addons/karpenter/nodepool/      #   NAP의 NodePool/AKSNodeClass CR 매니페스트
addons/kyverno/custom-policies/ #   이 저장소가 소유하는 ValidatingPolicy 매니페스트
scripts/          # 주석 규칙 검사기(.py다 - 아래 "게이트" 절 참고)
.githooks/        # pre-commit 훅
.github/workflows/verify.yml # CI. 훅과 같은 검사 + YAML 파싱·부모 차트 렌더·kyverno test
tests/kyverno/    # 커스텀 정책 픽스처. Application source 경로 밖이라 클러스터에 가지 않는다
```

## root App이 읽는 범위 — `include` allow-list

`bootstrap/root-app.yaml`은 `directory.include`에 적힌 경로만 매니페스트로 읽는다. 지금은
`projects/`·`clusters/**/cluster-secret.yaml`·`applicationsets/*.yaml`·`bootstrap/`의 두 Application
파일이다. **그 밖은 무엇이든 무시한다** — `addons/` 전체(부모 차트는 부모가, CR 매니페스트는 addon
Application이 따로 읽는다), helm values(`bootstrap/argocd-values.yaml`), 도구 파일 전부.

이 저장소는 `exclude`와 `+argocd:skip-file-rendering` 마커를 쓰지 않는다. 기각 근거는
`iac-module-library`의 `docs/architectures/gitops-hub-spoke/gitops.md` 「하지 않는 것」이 갖는다.

매니페스트 디렉토리를 새로 만들면 `include`에 한 줄 더한다. `applicationsets/`는 바로 아래 파일만
읽는다. ⚠️ `x/**/*.yaml`은 `x` 바로 아래 파일을 잡지 않는다 — `**` 뒤의 `/` 때문에 사이에 디렉토리가
하나 이상 있어야 매치되고, 빠진 파일은 오류 없이 무시되어 root App이 `Synced`로 남는다. ⚠️ **렌더가 깨지는 파일이 든 경로**를 `include`에
넣으면 그 spec이 적용된 뒤부터 자기 갱신이 멈춘다. root App은 자기 spec을 클러스터에 적용된
옛 spec으로 렌더한 뒤에야 갱신하는데, 그 렌더가 깨지면 갱신에 이르지 못한다. 그 파일을 고치는
커밋이 풀거나, `argocd-seed.sh`의 root Application 단계만 다시 돌려 커밋본 `root-app.yaml`을 손으로 다시 apply한다.

`addons/<addon>/<dir>/`는 값을 주입할 일이 없으면 평문 매니페스트 디렉토리다. 이 저장소의
셋(`gateway/shared-gateway`·`karpenter/nodepool`·`kyverno/custom-policies`)이 전부 그렇다.
per-cluster 값을 CR에 넣어야 하면 helm 차트여야 한다 — 부모 차트는 addon Application spec에 값을
적을 수 있지만 평문 디렉토리 source는 파일 안의 값을 치환하지 않기 때문이다.

## 부모 Application — 클러스터마다 하나

`applicationsets/platform.yaml`이 cluster Secret마다 부모 `<cluster>-platform`을 만들고, 부모가
`addons/platform/` 차트로 그 클러스터의 addon Application을 렌더한다. 부모를 두는 이유는 순서다.
부모가 addon Application을 자기 리소스로 sync해야 sync-wave가 설치 순서(앞 wave가 Healthy가 된 뒤
다음 wave)와 해제 순서(wave 역순, 삭제 완료 대기)가 된다. 설계 근거는 `iac-module-library`의
`docs/architectures/gitops-hub-spoke/ordering.md`와 `azure/README.md`가 갖는다.

| wave | addon | 기대는 것 |
|:---:|---|---|
| 0 | `karpenter-nodepool`(opt-in) · `gateway` | 컨트롤러와 CRD는 계층 1이 만든다(NAP · App Routing) |
| 1 | `kyverno` | 파드가 뜰 NAP 노드. 시스템 풀 taint를 견디지 않는다 |
| 2 | `kyverno-policies` · `kyverno-custom-policies` | 엔진 |

🔑 **Kyverno가 NodePool 뒤에 오는 것이 이 저장소의 핵심이다.** 해제가 역순이라 Kyverno와 그 삭제 훅
Job(`scale-to-zero`·`rm-webhooks`)이 NAP 노드가 살아 있을 때 끝난다. NodePool이 먼저 지워지면 그 Job이
`Pending`에 걸려 kyverno Application이 `deletionTimestamp`를 낀 채 남는다. ⚠️ `addon-karpenter`를
구독하지 않은 클러스터는 Kyverno가 뜰 노드가 없어 wave 1에서 멈춘다.

매니페스트마다 반복하지 않고 여기 한 번 적는다. 개별 템플릿 주석은 그 파일에만 참인 것만 갖는다.

| 항목 | 규약 |
|---|---|
| wave | addon Application의 `argocd.argoproj.io/sync-wave`. 기대는 addon보다 크게 둔다. 대기는 `bootstrap/argocd-values.yaml`의 Application health Lua가 있어야 선다. 없으면 wave가 생성 순서만 정한다 |
| 식별 라벨 | addon Application에 `platform.addon`·`platform.cluster`·`platform.wave`, 부모에 `platform.cluster`. 이름의 `<cluster>-` 접두사가 콘솔에서 잘려 addon이 가려지므로 식별은 라벨로 한다(`kubectl -n argocd get applications -l platform.cluster=<cluster> -L platform.addon,platform.wave`, `argocd app list -l platform.addon=<addon>`). 라벨과 sync-wave 어노테이션은 `_helpers.tpl`의 `platform.meta` 하나가 찍는다. 트리 노드 태그는 `bootstrap/argocd-values.yaml`의 `resource.customLabels`가 띄운다 |
| `finalizers` | 부모와 addon Application 모두 `resources-finalizer.argocd.argoproj.io`를 둔다. 부모의 것이 해제 때 addon을 wave 역순으로 지우고, addon의 것이 클러스터 실물을 지운다 |
| cluster-scoped CR | NodePool·AKSNodeClass·ValidatingPolicy는 cluster-scoped라 `destination.namespace`가 형식상 값이다 |
| 부모 `prune: true` | opt-in 해지(라벨 제거)가 부모의 prune으로 이루어진다. ⚠️ 그래서 `addons/platform/templates/`에서 파일을 지우면 등록된 전 클러스터에서 그 addon이 지워진다 |

⚠️ **돌고 있는 클러스터가 있을 때 ApplicationSet `platform`의 이름·selector나 addon 템플릿의
`metadata.name`을 바꾸지 않는다.** 이름이 바뀌면 삭제로 처리되고, finalizer가 **실물까지 prune한다.**
정리할 수 있는 시점은 전면 철거 이후 seed 이전뿐이다.

⚠️ **부모가 앞 wave를 기다리며 멈췄을 때**: 앞 wave의 addon이 Healthy가 되지 못하면 부모의 sync
operation이 끝나지 않고, 그동안 버전 표를 고친 커밋이 addon Application에 반영되지 않는다. ArgoCD의
sync 타임아웃 기본값이 무제한이라 스스로 풀리지 않는다. `argocd app terminate-op <cluster>-platform`으로
끊으면 다음 auto-sync가 새 커밋으로 돈다.

### 버전 표 — `addons/platform/values.yaml`

승인된 버전은 이 표에만 있다. 템플릿은 `tier`로 줄을 고를 뿐 버전을 적지 않는다. staged addon은
`versions.<addon>`에 `prd`·`nonprd` 두 줄을 나란히 둔다. 두 값이 다르면 승격이 진행 중이고, 같으면
끝난 것이다.

**이 저장소에서 staged는 Kyverno뿐이다.** 노드와 트래픽을 다루는 컨트롤러를 전부 관리형으로
받으므로(NAP·App Routing) 버전 핀을 가진 것이 엔진과 PSS 정책 둘뿐이다.

⚠️ `tier`가 `prd`·`nonprd`가 아니면 부모 차트가 `required`로 렌더를 실패시켜 그 클러스터의 부모가
`ComparisonError`로 멈춘다. `environment` 라벨이 없으면 부모 자체가 생기지 않고, ArgoCD는 대상
0개인 팬아웃을 오류로 보고하지 않는다.

## cluster Secret 라벨 계약

ApplicationSet `platform`이 읽거나 부모 차트에 넘기는 라벨이다.

| 라벨 | 읽는 쪽 | 값 | 빠지면 |
|---|---|---|---|
| `environment` | 부모 생성(존재) | `hub` · `dev` 등 | 부모가 생기지 않는다. 오류가 보고되지 않는다 |
| `tier` | 버전 표의 줄 선택 | `prd` \| `nonprd` | 부모 렌더가 `required`로 실패한다 |
| `addon-karpenter: enabled` | NodePool/AKSNodeClass 구독 | NAP을 켠 클러스터만 | NodePool이 빠지고 Kyverno가 뜰 노드가 없다 |

⚠️ **teardown은 `environment` 라벨을 먼저 떼고, 부모가 hub에서 사라진 뒤 Secret을 지운다.** 라벨을
떼면 부모가 지워지면서 addon을 wave 역순(정책 → Kyverno → NodePool·Gateway)으로 지운다. Secret을 먼저
지우면 ArgoCD가 목적지를 잃어 spoke 리소스를 지우지 않고 기록만 버린다. 명령 순서는
`aks-reference-infra`의 `spoke-lifecycle.md`가 갖는다. git 이력의 마지막 cluster-secret을 그대로
되살리면 라벨이 빠진 껍데기이고, 그 상태로는 부모가 생기지 않는다.

## 게이트 — 로컬 훅과 CI

이 저장소는 push가 곧 apply다. ArgoCD가 `main`을 pull로 reconcile하므로, 깨진 매니페스트를
막는 자리는 **머지 전**뿐이다. 두 층이 있다. 커밋 전 훅(clone마다 한 번 켠다)과, 같은 검사에
YAML 파싱·정책 판정을 더해 PR·main push에서 도는 `.github/workflows/verify.yml`이다.

```bash
git config core.hooksPath .githooks
brew install shellcheck gitleaks   # 셸·시크릿 게이트가 요구한다. 없으면 훅이 즉시 실패한다
```

`.githooks/pre-commit`이 staged 파일 중 `applicationsets/`·`addons/`·`projects/`·`clusters/`·`bootstrap/`·`tests/`의
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

`verify.yml`은 훅과 같은 검사(주석 규칙·`bash -n`·`shellcheck -x`, 버전을 로컬과 같게 핀)에
세 가지를 더한다. **YAML 전체 파싱**, **부모 차트 `helm lint`·`helm template`**(`required` 값은
ApplicationSet이 cluster Secret 라벨에서 주입하는 것이라 대표값을 `--set`으로 준다. 두 티어 × NAP
구독 유무를 모두 렌더하고, 없는 `tier`가 렌더 실패가 되는지 본다), **`kyverno test`**(`tests/kyverno/`의 픽스처로 커스텀
정책의 통과·거부·제외를 판정한다. 제외 조건 셋 — `control-plane` 라벨·`managedby=aks`·argocd —
이 각각 `Excluded`로 떨어지는지가 픽스처에 있다. CLI 버전은 kyverno 차트의 appVersion과 같아야
한다). 픽스처는 어떤 Application의
source 경로에도 들어가지 않는 `tests/`에 둔다 — `addons/` 아래 두면 Directory 타입 Application이
파드 픽스처를 클러스터에 적용한다.

⛔ ArgoCD의 렌더(Application 조립·파라미터 주입·`include` 판정)는 흉내 내지 않는다. 그것은
클러스터에서 ArgoCD가 판정하고, seed 뒤 `argocd app diff`가 그 자리다. CI가 보는 것은 차트와 정책
파일 자체다.

의도적 우회는 `git commit --no-verify`이고, 사유를 커밋 메시지에 남긴다. CI는 우회하지 않는다.

`eks-platform-gitops`가 같은 게이트를 같은 내용으로 갖는다. 한쪽을 고치면 다른 쪽도 함께
고친다 — 드리프트를 검사하는 장치는 없다.

seed 절차(workbench 준비 · `argocd-seed.sh` 실행 순서)는 `aks-reference-infra`의
`docs/hub-lifecycle.md` 「GitOps 씨딩」이 소유한다. 저장소가 public이라 클론에도 ArgoCD의 읽기에도
자격증명이 없다. 스크립트는 preflight에서 `root-app.yaml`의 `repoURL`을 익명으로 `ls-remote`해 그
전제를 확인한다 — 저장소가 private으로 돌아가면 sync가 조용히 멈추기 때문이다.

---

## 라이선스

[MIT](LICENSE).
