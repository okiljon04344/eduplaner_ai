"""Creates emulator test users for school.test: a teacher-admin and a student."""
import json
import urllib.request

AUTH = "http://127.0.0.1:9099"
FS = "http://127.0.0.1:8085/v1/projects/eduplannerai-97365/databases/(default)/documents"
H = {"Content-Type": "application/json", "Authorization": "Bearer owner"}
PW = "test-pass-123"


def call(method, url, body=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers=H, method=method)
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read() or b"{}")


def fs_value(v):
    if v is None:
        return {"nullValue": None}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: fs_value(x) for k, x in v.items()}}}
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, list):
        return {"arrayValue": {"values": [fs_value(x) for x in v]}}
    return {"stringValue": v}


def put(path, data):
    call("PATCH", f"{FS}/{path}?" + "&".join(f"updateMask.fieldPaths={k}" for k in data),
         {"fields": {k: fs_value(v) for k, v in data.items()}})


def user(email, name, extra):
    res = call("POST", f"{AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake",
               {"email": email, "password": PW, "returnSecureToken": True})
    uid = res["localId"]
    call("POST", f"{AUTH}/identitytoolkit.googleapis.com/v1/projects/eduplannerai-97365/accounts:update",
         {"localId": uid, "emailVerified": True})
    put(f"users/{uid}", {"uid": uid, "name": name, "email": email, "schoolDomain": "school.test",
                         "schoolType": "vocational", "school": "テスト学校", **extra})
    return uid


teacher = user("tanaka@school.test", "田中 先生", {"grade": "1", "course": "農業"})
student = user("s1001@school.test", "学生 一郎", {"grade": "1", "course": "農業"})
# Non-admin teacher: may change only lessons whose cell names 鈴木.
suzuki = user("suzuki@school.test", "鈴木 先生", {})
# Plain homeroom teacher (not admin): 担任 of 2年・観光.
yamada = user("yamada@school.test", "山田 先生", {})
put("schools/school.test", {
    "admins": [teacher],
    "teachers": ["tanaka@school.test", "suzuki@school.test", "yamada@school.test"],
    "teacherProfiles": {
        "tanaka@school.test": {"name": "田中", "homeroom": {"grade": 1, "course": "農業"}},
        "suzuki@school.test": {"name": "鈴木", "homeroom": None},
        "yamada@school.test": {"name": "山田", "homeroom": {"grade": 2, "course": "観光"}},
    },
})
print("teacher", teacher, "student", student, "suzuki", suzuki)
