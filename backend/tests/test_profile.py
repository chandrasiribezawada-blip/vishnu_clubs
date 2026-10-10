API = "/api/v1"


def _register(client, suffix, registration_number, department, year, section=None):
    body = {
        "full_name": f"Student {suffix}",
        "email": f"{suffix}@example.edu",
        "registration_number": registration_number,
        "department": department,
        "year": year,
        "phone_number": "+15551234567",
        "password": "correct-horse-battery",
    }
    if section is not None:
        body["section"] = section
    response = client.post(f"{API}/auth/register", json=body)
    assert response.status_code == 201, response.text
    return response.json()


def _auth(tokens):
    return {"Authorization": f"Bearer {tokens['access_token']}"}


def test_profile_requires_login(client):
    assert client.get(f"{API}/me/profile").status_code == 401


def test_student_sees_only_their_own_profile(client):
    first = _register(client, "alpha", "REG-A", "CSE", "2nd Year", section="B")
    second = _register(client, "beta", "REG-B", "ECE", "3rd Year")

    mine = client.get(f"{API}/me/profile", headers=_auth(first))
    assert mine.status_code == 200, mine.text
    assert mine.json() == {
        "registration_number": "REG-A",
        "department": "CSE",
        "year": "2nd Year",
        "section": "B",
        "phone_number": "+15551234567",
    }

    other = client.get(f"{API}/me/profile", headers=_auth(second))
    assert other.status_code == 200
    assert other.json()["registration_number"] == "REG-B"
    assert other.json()["section"] is None