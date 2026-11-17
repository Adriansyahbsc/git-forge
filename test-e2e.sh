#!/bin/bash
# End-to-end test of the forge with the real git CLI + REST + GraphQL + MCP.
set -u
BASE=http://127.0.0.1:3457
TOK=testtoken123
AUTH="Authorization: Bearer $TOK"
OWNER=adaiversen
W=/tmp/forge-e2e
rm -rf "$W"; mkdir -p "$W"; cd "$W"
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=http.extraHeader
export GIT_CONFIG_VALUE_0="Authorization: Bearer $TOK"
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=t@example.invalid
step(){ echo; echo "=== $* ==="; }

step "1. Create repo via REST API"
curl -s -X POST -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"name":"demo","private":true,"description":"e2e demo repo"}' \
  $BASE/api/v3/user/repos -w "\nHTTP %{http_code}\n"

step "2. Clone the (empty) repo"
git clone "$BASE/$OWNER/demo.git" clone1 2>&1 | tail -2
cd clone1
git symbolic-ref HEAD refs/heads/main 2>/dev/null || true
echo "hello forge" > hello.txt
git add . && git commit -q -m "first commit"
git branch -M main

step "3. Push first commit"
git push origin main 2>&1 | tail -3

step "4. Clone again elsewhere and verify file"
cd "$W"
git clone -q "$BASE/$OWNER/demo.git" clone2 2>&1 | tail -1
echo "--- clone2/hello.txt:"; cat clone2/hello.txt
echo "--- clone2 log:"; git -C clone2 log --oneline | head -3

step "5. Second commit in clone2, push, then fetch+pull in clone1"
cd clone2
echo "second line" >> hello.txt
mkdir -p docs && echo "# Docs" > docs/readme.md
git add . && git commit -q -m "second commit"
git push origin main 2>&1 | tail -2
cd "$W/clone1"
git pull -q origin main 2>&1 | tail -1
echo "--- clone1/hello.txt after pull:"; cat hello.txt; ls docs

step "6. Non-fast-forward push must be refused"
cd "$W"
git clone -q "$BASE/$OWNER/demo.git" clone3
cd clone3
git reset -q --hard HEAD~1
echo "divergent" > hello.txt
git add . && git commit -q -m "divergent commit"
git push origin main 2>&1 | tail -4 || true

step "7. REST: contents API round-trip"
curl -s -X PUT -H "$AUTH" -H 'Content-Type: application/json' \
  -d "{\"message\":\"add via api\",\"content\":\"$(echo -n 'api file body' | base64 -w0)\"}" \
  $BASE/api/v3/repos/$OWNER/demo/contents/api.txt -w "\nHTTP %{http_code}\n" | head -c 400; echo
curl -s -H "$AUTH" $BASE/api/v3/repos/$OWNER/demo/contents/api.txt | head -c 300; echo
echo "--- branches:"; curl -s -H "$AUTH" $BASE/api/v3/repos/$OWNER/demo/branches
echo; echo "--- commits on main:"; curl -s -H "$AUTH" "$BASE/api/v3/repos/$OWNER/demo/commits?sha=main" | head -c 300; echo

step "8. REST: label + issue + comment"
curl -s -X POST -H "$AUTH" -d '{"name":"bug","color":"d73a4a"}' $BASE/api/v3/repos/$OWNER/demo/labels -w "\nHTTP %{http_code}\n"
curl -s -X POST -H "$AUTH" -d '{"title":"It broke","body":"steps to repro","labels":["bug"]}' $BASE/api/v3/repos/$OWNER/demo/issues -w "\nHTTP %{http_code}\n" | head -c 400; echo
curl -s -X POST -H "$AUTH" -d '{"title":"Bad label","labels":["nope"]}' $BASE/api/v3/repos/$OWNER/demo/issues -w "\nHTTP %{http_code} (expect 422)\n"
curl -s -X POST -H "$AUTH" -d '{"body":"looking into it"}' $BASE/api/v3/repos/$OWNER/demo/issues/1/comments -w "\nHTTP %{http_code}\n" | head -c 200; echo
curl -s -H "$AUTH" "$BASE/api/v3/repos/$OWNER/demo/issues?state=open" | head -c 300; echo

step "9. REST: branch via git/refs, PR, files, squash merge"
HEADSHA=$(git -C "$W/clone2" rev-parse main)
curl -s -X POST -H "$AUTH" -d "{\"ref\":\"refs/heads/feature\",\"sha\":\"$HEADSHA\"}" $BASE/api/v3/repos/$OWNER/demo/git/refs -w "\nHTTP %{http_code}\n"
cd "$W/clone2"
git fetch -q origin && git checkout -q -b feature origin/feature 2>/dev/null || git checkout -q feature
echo "feature work" > feature.txt
git add . && git commit -q -m "feature commit"
git push -q origin feature 2>&1 | tail -1
curl -s -X POST -H "$AUTH" -d '{"title":"Add feature","body":"please merge","head":"feature","base":"main"}' $BASE/api/v3/repos/$OWNER/demo/pulls -w "\nHTTP %{http_code}\n" | head -c 500; echo
PRNUM=$(curl -s -H "$AUTH" "$BASE/api/v3/repos/$OWNER/demo/pulls?state=all" | grep -o '"number":[0-9]*' | tail -1 | cut -d: -f2)
echo "PR number: $PRNUM"
echo "--- PR files:"; curl -s -H "$AUTH" $BASE/api/v3/repos/$OWNER/demo/pulls/$PRNUM/files; echo
echo "--- merge:"; curl -s -X PUT -H "$AUTH" -d '{"merge_method":"squash"}' $BASE/api/v3/repos/$OWNER/demo/pulls/$PRNUM/merge -w "\nHTTP %{http_code}\n"
echo "--- PR after merge:"; curl -s -H "$AUTH" $BASE/api/v3/repos/$OWNER/demo/pulls/$PRNUM | head -c 350; echo
cd "$W" && git clone -q "$BASE/$OWNER/demo.git" clone4 && echo "--- clone4 files after merge:" && ls clone4 && cat clone4/feature.txt

step "10. GraphQL: viewer, repository, createIssue, openIssues"
curl -s -X POST -H "$AUTH" -d '{"query":"query { viewer { login } }"}' $BASE/api/graphql; echo
REPOID=$(curl -s -X POST -H "$AUTH" -d "{\"query\":\"query { repository(owner: \\\"$OWNER\\\", name: \\\"demo\\\") { id databaseId nameWithOwner defaultBranchRef { name } } }\"}" $BASE/api/graphql | tee /tmp/gql-repo.json | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
cat /tmp/gql-repo.json; echo
curl -s -X POST -H "$AUTH" -d "{\"query\":\"mutation { createIssue(input: {repositoryId: \\\"$REPOID\\\", title: \\\"from graphql\\\", body: \\\"gql body\\\"}) { issue { number title state } } }\"}" $BASE/api/graphql; echo
curl -s -X POST -H "$AUTH" -d "{\"query\":\"query { repository(owner: \\\"$OWNER\\\", name: \\\"demo\\\") { issues(first: 10, states: [OPEN], orderBy: {field: CREATED_AT, direction: DESC}) { nodes { number title state } } } }\"}" $BASE/api/graphql; echo
curl -s -X POST -H "$AUTH" -d '{"query":"query { __type(name: \"Issue\") { fields { name } } }"}' $BASE/api/graphql; echo

step "11. MCP: discover, tools/list, create_issue, list_issues, rest parity"
curl -s -X POST -H "$AUTH" -d '{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{}}' $BASE/mcp; echo
curl -s -X POST -H "$AUTH" -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' $BASE/mcp | head -c 300; echo
curl -s -X POST -H "$AUTH" -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"create_issue","arguments":{"owner":"'$OWNER'","repo":"demo","title":"from mcp","body":"mcp body"}}}' $BASE/mcp | head -c 400; echo
curl -s -X POST -H "$AUTH" -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_issues","arguments":{"owner":"'$OWNER'","repo":"demo","state":"open"}}}' $BASE/mcp | head -c 400; echo
curl -s -X POST -H "$AUTH" -d '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope_tool","arguments":{}}}' $BASE/mcp; echo
curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":6,"method":"tools/list","params":{}}' $BASE/mcp -w "\nHTTP %{http_code} (expect 401, no auth)\n"
echo "--- REST sees MCP issue:"; curl -s -H "$AUTH" "$BASE/api/v3/repos/$OWNER/demo/issues?state=open" | grep -o '"title":"[^"]*"'; echo

step "12. Shallow clone + foreign owner 404 + missing repo 404"
git clone -q --depth 1 "$BASE/$OWNER/demo.git" clone5 && echo "shallow clone OK: $(cat clone5/hello.txt | head -1)"
curl -s -H "$AUTH" $BASE/api/v3/repos/olgabauer/demo -w "\nHTTP %{http_code} (expect 404 foreign owner)\n"
curl -s -H "$AUTH" $BASE/api/v3/repos/$OWNER/nope -w "\nHTTP %{http_code} (expect 404)\n"
curl -s "$BASE/$OWNER/nope.git/info/refs?service=git-upload-pack" -H "$AUTH" -w "\nHTTP %{http_code} (expect 404 missing repo git)\n" | tail -2

echo; echo "=== E2E DONE ==="
