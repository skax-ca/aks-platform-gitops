#!/usr/bin/env bash
#V# ═══════════════════════════════════════════════════════════════════════════
#V#  VENDORED COPY — ⛔ 이 파일을 편집하지 마시오.
#V#
#V#  SSOT : skax-ca/iac-module-library · scripts/argocd-seed.sh
#V#  출처 : 0d342a04b2d62d7fbe73b7302219910960e04918  (2026-08-07)
#V#  근거 : aks-reference-infra .omc/plans/aks-platform-gitops-scaffold.md 6절
#V#         Follow-up 1(ArgoCD 자기관리 파일 vendoring) - AWS 원본
#V#         skax-ca/eks-platform-gitops의 bootstrap/argocd-seed.sh가 이미 이 커밋을
#V#         같은 방식으로 vendoring한 전례를 그대로 승계(스크립트 자체는 순수 kubectl/helm
#V#         이라 클라우드 무관 - AWS 특화 로직 없음, 2026-09-04 원본 대조로 확인).
#V#
#V#  왜 사본이 여기 있나 — Azure workbench(aks-workbench-v0.1.0 소비, 사설 클러스터 접근
#V#  환경)는 이 저장소가 아니라 aks-reference-infra의 live/hub/workbench가 별도 세션에서
#V#  구축 중이며 2026-09-04 기준 미완료다. workbench가 준비되면 이 저장소를 clone하는
#V#  것만으로 매니페스트와 스크립트가 함께 오도록 사본을 여기 둔다. 두 번째 배달
#V#  메커니즘을 만들지 않는다.
#V#
#V#  ⚠️ 경쟁 SSOT가 아니라 vendoring이다. 구분 기준은 "어디를 고치는가" 하나다 —
#V#     고칠 일이 생기면 **모듈 repo를 고치고 여기로 다시 복사**한다. 여기서 고치면 그때 drift다.
#V#
#V#  🔍 드리프트 검사 (모듈 repo 체크아웃에서, <gitops>는 이 저장소 경로):
#V#     diff <(grep -v '^#V#' <gitops>/bootstrap/argocd-seed.sh) scripts/argocd-seed.sh
#V#     ⇒ 이 배너를 뺀 나머지는 SSOT와 **바이트 단위로 같아야 한다.**
#V#     배너 줄에 전부 #V# 접두를 둔 이유가 이것이다 — 검사를 한 줄로 끝내려고.
#V#
#V#  ⚠️ 이 vendoring 시점(2026-09-04)에 module-library 작업 트리에는 scripts/argocd-seed.sh가
#V#     더 이상 없다(commit 962e481/845a96a의 docs/modules 재구성 중 이동·삭제된 것으로
#V#     추정, git log로 확인) - 위 SHA로만 조회 가능하다. 재검토 필요: 이 스크립트를
#V#     다시 vendoring할 일이 생기면 module-library에 먼저 복원할지, 이 사본을 새 SSOT로
#V#     승격할지 그때 결정한다(AWS 원본 저장소도 같은 SHA 참조를 그대로 쓰고 있어 이
#V#     저장소만의 문제가 아님).
#V# ═══════════════════════════════════════════════════════════════════════════
#
# argocd-seed.sh — self-managed ArgoCD 부트스트랩 seed (workbench에서 사람이 실행)
#
# 설계 SSOT:
#   aks-reference-infra .omc/plans/aks-platform-gitops-scaffold.md (이 저장소의 소비 설계)
#   AWS 원본 skax-ca/eks-platform-gitops의 bootstrap/argocd-seed.sh (1:1 대응 전례)
#
# ⭐ 자기소멸(self-superseding) 원칙이 이 스크립트의 설계 제약이다.
#    이 스크립트는 매니페스트를 **생성하지 않는다** — GitOps 저장소에 커밋된 파일을
#    **그대로 apply**한다. 생성하면 커밋본과 바이트가 달라지고, 그 차이가 영구 드리프트로 남는다.
#    그래서 --set도, 인라인 heredoc 매니페스트도 쓰지 않는다.
#    ⚠️ 예외는 단 하나: repository Secret(2단계). private key를 담아 커밋할 수 없다.
#
# ⚠️ 이 repo는 배포하지 않는다. 이 스크립트는 **소비 프로젝트가 실행하는 절차**이며,
#    여기서는 재사용 자산으로만 소유한다.
#
# ⚠️ bash 3.2 호환으로 쓴다 — macOS 기본 bash가 3.2이고(실측), 이 스크립트는 workbench
#    뿐 아니라 팀원 노트북에서 --dry-run으로도 돌린다. 연상배열·mapfile·${var^^}를 쓰지 않는다.
set -Eeuo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# 사용법
# ─────────────────────────────────────────────────────────────────────────────
usage() {
  cat <<'USAGE'
사용법: argocd-seed.sh [--dry-run] [--from STEP] [--to STEP]

GitOps 저장소를 pull하는 self-managed ArgoCD를 부트스트랩한다.
단계는 순서대로 실행되며 각 단계가 다음 단계의 전제다.

  0  helm install argo-cd            (저장소의 values 파일 그대로)
  2  GitHub App repository Secret    (자기소멸 원칙의 유일한 예외)
  3  platform AppProject
  4  cluster Secret                  (라벨·이름 공급 — "등록"이 아니다)
  5  root Application                (자기 자신을 흡수)

  ℹ️ 1단계는 self-managed에 없다 — ArgoCD가 클러스터 안에 있다.
     spoke 클러스터를 붙일 때만 필요하며 그것은 Terraform 소관이다.

필수 환경변수
  GITOPS_REPO_DIR       체크아웃된 GitOps 저장소 경로 (매니페스트의 출처)
  CLUSTER_DIR           seed할 클러스터 디렉토리 (GITOPS_REPO_DIR 기준 상대경로)
                        예: clusters/hub/aks-demo-hub-krc-main-01
  GH_APP_ID             GitHub App ID
  GH_APP_INSTALLATION_ID GitHub App Installation ID
  GH_APP_PRIVATE_KEY    private key(.pem) 파일 경로
  GITOPS_REPO_URL       ArgoCD가 읽을 저장소 URL (repository Secret의 url)

선택 환경변수
  ARGOCD_NAMESPACE      기본 argocd
  ARGOCD_CHART_VERSION  기본 10.3.0        (올릴 땐 argocd CLI도 같이)
  ARGOCD_VALUES         기본 bootstrap/argocd-values.yaml   (GITOPS_REPO_DIR 기준 상대경로)
  ARGOCD_RELEASE        기본 argocd

예시
  export GITOPS_REPO_DIR=~/aks-platform-gitops
  export CLUSTER_DIR=clusters/hub/aks-demo-hub-krc-main-01
  export GITOPS_REPO_URL=https://github.com/skax-ca/aks-platform-gitops.git
  export GH_APP_ID=... GH_APP_INSTALLATION_ID=... GH_APP_PRIVATE_KEY=~/key.pem
  ./argocd-seed.sh --dry-run     # 먼저 이것부터 돌린다
  ./argocd-seed.sh
USAGE
}

DRY_RUN=0
FROM_STEP=0
TO_STEP=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --from)    FROM_STEP="${2:?--from에 단계 번호가 필요하다}"; shift 2 ;;
    --to)      TO_STEP="${2:?--to에 단계 번호가 필요하다}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "알 수 없는 인자: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
# 출력
# ─────────────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_HEAD=$'\033[1;36m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_ERR=''; C_HEAD=''; C_OFF=''
fi
step() { printf '\n%s━━ 단계 %s · %s%s\n' "$C_HEAD" "$1" "$2" "$C_OFF"; }
ok()   { printf '%s  ✅ %s%s\n' "$C_OK"   "$1" "$C_OFF"; }
warn() { printf '%s  ⚠️  %s%s\n' "$C_WARN" "$1" "$C_OFF"; }
die()  { printf '%s  ❌ %s%s\n' "$C_ERR"  "$1" "$C_OFF" >&2; exit 1; }
run()  {
  if (( DRY_RUN )); then printf '     [dry-run] %s\n' "$*"; else "$@"; fi
}

# 실행할 단계인지
want() { local s=$1; (( s >= FROM_STEP && s <= TO_STEP )); }

# ─────────────────────────────────────────────────────────────────────────────
# 사전 점검 — 여기서 막는 것이 클러스터에서 반쯤 진행된 상태보다 싸다
# ─────────────────────────────────────────────────────────────────────────────
step "preflight" "전제 확인"

for v in GITOPS_REPO_DIR CLUSTER_DIR GH_APP_ID GH_APP_INSTALLATION_ID GH_APP_PRIVATE_KEY GITOPS_REPO_URL; do
  [[ -n "${!v:-}" ]] || die "필수 환경변수 $v가 비어 있다. --help 참조"
done

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.3.0}"
ARGOCD_VALUES="${ARGOCD_VALUES:-bootstrap/argocd-values.yaml}"
ARGOCD_RELEASE="${ARGOCD_RELEASE:-argocd}"

# 경로 정규화 (~ 확장은 호출자 셸이 한다. 여기서는 존재만 본다)
[[ -d "$GITOPS_REPO_DIR" ]]        || die "GITOPS_REPO_DIR이 디렉토리가 아니다: $GITOPS_REPO_DIR"
[[ -f "$GH_APP_PRIVATE_KEY" ]]     || die "private key 파일이 없다: $GH_APP_PRIVATE_KEY"

for c in kubectl helm; do
  command -v "$c" >/dev/null || die "$c가 PATH에 없다"
done
ok "kubectl · helm 존재"

# ⭐ 자기소멸 원칙의 집행 — 저장소가 커밋 상태여야 한다.
#    dirty인 채로 seed하면 apply된 내용이 저장소 어디에도 없고, root App이 흡수한 순간
#    selfHeal이 그것을 되돌린다. 증상은 "방금 넣은 설정이 사라진다"이고 원인을 가리키지 않는다.
if git -C "$GITOPS_REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  if [[ -n "$(git -C "$GITOPS_REPO_DIR" status --porcelain)" ]]; then
    git -C "$GITOPS_REPO_DIR" status --short | sed 's/^/       /'
    die "GitOps 저장소에 커밋되지 않은 변경이 있다 — 자기소멸 원칙이 깨진다. 커밋·push 후 다시 실행하라"
  fi
  local_head=$(git -C "$GITOPS_REPO_DIR" rev-parse --short HEAD)
  ok "저장소 clean · HEAD=$local_head"
  if ! git -C "$GITOPS_REPO_DIR" diff --quiet HEAD "@{upstream}" 2>/dev/null; then
    warn "로컬 HEAD가 upstream과 다르다 — ArgoCD는 **원격**을 읽는다. push했는지 확인하라"
  fi
else
  warn "GITOPS_REPO_DIR이 git 저장소가 아니다 — 자기소멸 원칙을 기계로 확인할 수 없다"
fi

# 매니페스트 3종 존재 확인
PROJECT_FILE="$GITOPS_REPO_DIR/projects/platform.yaml"
CLUSTER_FILE="$GITOPS_REPO_DIR/$CLUSTER_DIR/cluster-secret.yaml"
ROOTAPP_FILE="$GITOPS_REPO_DIR/bootstrap/root-app.yaml"
VALUES_FILE="$GITOPS_REPO_DIR/$ARGOCD_VALUES"
for f in "$PROJECT_FILE" "$CLUSTER_FILE" "$ROOTAPP_FILE" "$VALUES_FILE"; do
  [[ -f "$f" ]] || die "필요한 파일이 없다: $f"
done
ok "매니페스트 3종 + values 존재"

# 클러스터 도달성 — private endpoint라 workbench 밖에서는 여기서 막힌다
if (( ! DRY_RUN )); then
  kubectl cluster-info >/dev/null 2>&1 \
    || die "클러스터에 닿지 않는다. workbench에서 실행 중인지, kubeconfig가 맞는지 확인하라"
  ok "클러스터 도달 · context=$(kubectl config current-context)"
fi

if (( DRY_RUN )); then
  warn "dry-run 모드 — 아무것도 바꾸지 않는다"
  warn "검증하지 않는다 — ArgoCD CR은 CRD라 클라이언트 dry-run이 discovery API를 요구한다(오프라인 불가)"
  warn "진짜 검증은 실제 실행 때 서버 dry-run이 한다. 여기서는 '무엇을 어디서 적용하는지'만 본다"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 0단계 — ArgoCD 설치 (저장소의 values 그대로)
# ─────────────────────────────────────────────────────────────────────────────
if want 0; then
  step 0 "helm install argo-cd $ARGOCD_CHART_VERSION"
  run helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
  run helm repo update argo >/dev/null
  # ⛔ --set을 쓰지 않는다. values는 저장소 커밋본 하나뿐이어야 한다(자기소멸 원칙).
  run helm upgrade --install "$ARGOCD_RELEASE" argo/argo-cd \
    --namespace "$ARGOCD_NAMESPACE" --create-namespace \
    --version "$ARGOCD_CHART_VERSION" \
    --values "$VALUES_FILE" \
    --wait --timeout 10m
  ok "helm release '$ARGOCD_RELEASE' 적용됨"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2단계 — GitHub App repository Secret
#   ⚠️ 자기소멸 원칙의 유일한 예외 — private key라 저장소에 커밋할 수 없다.
#      따라서 이 Secret만 GitOps 관리 밖에 남는다. root App의 prune:false가 이것을 지켜준다.
# ─────────────────────────────────────────────────────────────────────────────
if want 2; then
  step 2 "GitHub App repository Secret (GitOps 관리 밖 — 의도된 예외)"
  if (( DRY_RUN )); then
    printf '     [dry-run] kubectl create secret argocd-repo-gitops (private key 주입)\n'
  else
    kubectl create secret generic argocd-repo-gitops \
      --namespace "$ARGOCD_NAMESPACE" \
      --from-literal=type=git \
      --from-literal=url="$GITOPS_REPO_URL" \
      --from-literal=githubAppID="$GH_APP_ID" \
      --from-literal=githubAppInstallationID="$GH_APP_INSTALLATION_ID" \
      --from-file=githubAppPrivateKey="$GH_APP_PRIVATE_KEY" \
      --dry-run=client -o yaml \
      | kubectl label --local -f - --dry-run=client -o yaml \
          argocd.argoproj.io/secret-type=repository \
      | kubectl apply -f -
  fi
  ok "repository Secret 'argocd-repo-gitops' 적용됨"
  warn "이 Secret은 저장소에 없다 — 삭제되면 모든 sync가 멈춘다. 복구 절차에 포함하라"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3·4·5단계 — 커밋본을 그대로 apply. 각 단계가 다음의 전제다.
#   서버 dry-run을 먼저 돌려 스키마·권한 문제를 apply 전에 드러낸다.
# ─────────────────────────────────────────────────────────────────────────────
apply_manifest() {
  local n=$1 label=$2 file=$3
  step "$n" "$label"
  printf '     출처: %s\n' "${file#"$GITOPS_REPO_DIR"/}"
  if (( DRY_RUN )); then
    # ⚠️ dry-run에서는 **kubectl을 아예 부르지 않는다.** AppProject·Application은 **CRD**라
    #    kubectl이 RESTMapping을 풀려면 discovery API(`/api`)를 쳐야 한다. 검증을 꺼도
    #    그 호출은 남는다 ⇒ **ArgoCD CR은 클라이언트 dry-run으로 오프라인 검증이 불가능하다.**
    #    클러스터는 private이므로 팀원 노트북에서는 늘 막힌다.
    #    ⇒ dry-run의 역할을 "검증"이 아니라 **"무엇을 어디서 적용하는지 보여주기"**로 좁힌다.
    printf '     %-14s %s\n' "kind/name:" \
      "$(awk '/^kind:/{k=$2} /^metadata:/{m=1} m&&/^  name:/{print k"/"$2; exit}' "$file")"
  else
    # 서버 dry-run — 스키마·admission·권한을 실제로 통과하는지 apply 전에 본다.
    kubectl apply --dry-run=server -f "$file" >/dev/null \
      || die "서버 dry-run 실패 — apply하지 않았다: $file"
    kubectl apply -f "$file" | sed 's/^/     /'
  fi
  ok "$label 적용됨"
}

# ⚠️ `want 3 && apply_manifest ...`로 쓰지 않는다.
#    실측(bash 3.2/5.x): `set -e`는 && 리스트의 앞 명령 실패를 면제하므로 **조기 종료는 없다.**
#    문제는 다른 데 있다 — 그런 줄이 **마지막 문장이면 스크립트 종료 코드가 1**이 된다.
#    즉 `--to 4`로 정상 실행한 seed가 호출자(CI·wrapper)에게 **실패로 보인다.**
#    if 블록은 건너뛰어도 0이다.
if want 3; then apply_manifest 3 "platform AppProject" "$PROJECT_FILE"; fi
if want 4; then apply_manifest 4 "cluster Secret"      "$CLUSTER_FILE"; fi
if want 5; then apply_manifest 5 "root Application"    "$ROOTAPP_FILE"; fi

# ─────────────────────────────────────────────────────────────────────────────
# 검증 — "적용됐다"와 "동작한다"는 다르다
# ─────────────────────────────────────────────────────────────────────────────
if (( ! DRY_RUN )) && want 5; then
  step "verify" "흡수 확인"
  cat <<VERIFY
     아래를 사람이 확인한다(자동 판정하지 않는다 — 실패 모드가 여러 겹이다):

     1) root App이 저장소를 실제로 읽었는가
        kubectl -n $ARGOCD_NAMESPACE get application root-app \\
          -o jsonpath='{.status.sync.revision}{"\n"}'
        ⚠️ 값이 'main'이면 아직 **설정값**이다. 실제 커밋 SHA여야 pull 성공이다.

     2) Synced / Healthy인가
        kubectl -n $ARGOCD_NAMESPACE get application root-app \\
          -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'

     3) cluster Secret이 내장 in-cluster를 대체했는가 / 중복인가
        argocd cluster list        # 또는 UI의 Settings → Clusters

     4) UI 접근
        kubectl -n $ARGOCD_NAMESPACE port-forward svc/argocd-server 8080:443
        → https://localhost:8080  (자체 서명 인증서 경고는 정상이다)
        초기 비밀번호:
        kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret \\
          -o jsonpath='{.data.password}' | base64 -d

     ⛔ 마지막으로 **비밀번호를 바꾸고 초기 Secret을 지운다**(선택이 아니라 완료 조건):
        kubectl -n $ARGOCD_NAMESPACE delete secret argocd-initial-admin-secret
VERIFY
fi

printf '\n%s완료.%s\n' "$C_OK" "$C_OFF"
