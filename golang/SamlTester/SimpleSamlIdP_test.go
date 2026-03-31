package main

import (
	"github.com/crewjam/saml"
	"github.com/crewjam/saml/samlidp"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestReplaceGroupAttributeWithRoles(t *testing.T) {
	session := &saml.Session{
		Groups: []string{"users", "admins"},
		CustomAttributes: []saml.Attribute{{
			FriendlyName: "existing",
			Name:         "existing",
		}},
	}

	replaceGroupAttributeWithRoles(session)

	if len(session.Groups) != 0 {
		t.Fatalf("expected groups to be cleared, got %v", session.Groups)
	}
	if len(session.CustomAttributes) != 2 {
		t.Fatalf("expected 2 custom attributes, got %d", len(session.CustomAttributes))
	}

	roles := session.CustomAttributes[1]
	if roles.FriendlyName != defaultGroupAttributeName {
		t.Fatalf("expected %s friendly name, got %q", defaultGroupAttributeName, roles.FriendlyName)
	}
	if roles.Name != defaultGroupAttributeName {
		t.Fatalf("expected %s attribute name, got %q", defaultGroupAttributeName, roles.Name)
	}
	if len(roles.Values) != 2 {
		t.Fatalf("expected 2 role values, got %d", len(roles.Values))
	}
	if roles.Values[0].Value != "users" || roles.Values[1].Value != "admins" {
		t.Fatalf("unexpected role values: %+v", roles.Values)
	}
}

func TestReplaceGroupAttributeWithRolesSkipsEmptyGroups(t *testing.T) {
	session := &saml.Session{}

	replaceGroupAttributeWithRoles(session)

	if len(session.CustomAttributes) != 0 {
		t.Fatalf("expected no custom attributes, got %d", len(session.CustomAttributes))
	}
}

func TestReplaceGroupAttributeWithRolesUsesEnvOverride(t *testing.T) {
	t.Setenv("GROUP_ATTRIBUTE_NAME", "CustomRoles")

	session := &saml.Session{
		Groups: []string{"users"},
	}

	replaceGroupAttributeWithRoles(session)

	roles := session.CustomAttributes[0]
	if roles.FriendlyName != "CustomRoles" {
		t.Fatalf("expected CustomRoles friendly name, got %q", roles.FriendlyName)
	}
	if roles.Name != "CustomRoles" {
		t.Fatalf("expected CustomRoles attribute name, got %q", roles.Name)
	}
}

func TestGroupAttributeStoreTransformsStoredSessions(t *testing.T) {
	store := groupAttributeStore{store: &samlidp.MemoryStore{}}
	session := &saml.Session{
		ID:     "session-1",
		Groups: []string{"users", "ipausers"},
	}

	if err := store.Put("/sessions/session-1", session); err != nil {
		t.Fatalf("put session: %v", err)
	}

	if len(session.Groups) != 0 {
		t.Fatalf("expected session groups to be cleared after put, got %v", session.Groups)
	}
	if len(session.CustomAttributes) != 1 {
		t.Fatalf("expected one custom attribute after put, got %d", len(session.CustomAttributes))
	}

	var stored saml.Session
	if err := store.Get("/sessions/session-1", &stored); err != nil {
		t.Fatalf("get session: %v", err)
	}

	if len(stored.Groups) != 0 {
		t.Fatalf("expected stored session groups to be cleared, got %v", stored.Groups)
	}
	if len(stored.CustomAttributes) != 1 {
		t.Fatalf("expected one custom attribute in stored session, got %d", len(stored.CustomAttributes))
	}
	if stored.CustomAttributes[0].FriendlyName != defaultGroupAttributeName {
		t.Fatalf("expected %s friendly name, got %q", defaultGroupAttributeName, stored.CustomAttributes[0].FriendlyName)
	}
}

func TestGroupAttributeStoreTransformsDoublePointerSessions(t *testing.T) {
	store := groupAttributeStore{store: &samlidp.MemoryStore{}}
	session := &saml.Session{
		ID:     "session-2",
		Groups: []string{"users", "ipausers"},
	}

	if err := store.Put("/sessions/session-2", &session); err != nil {
		t.Fatalf("put session pointer: %v", err)
	}

	if len(session.Groups) != 0 {
		t.Fatalf("expected session groups to be cleared after put, got %v", session.Groups)
	}
	if len(session.CustomAttributes) != 1 {
		t.Fatalf("expected one custom attribute after put, got %d", len(session.CustomAttributes))
	}
}

func TestShouldResumeSAMLLogin(t *testing.T) {
	request := httptest.NewRequest("POST", "http://idp.test/login", strings.NewReader("user=alice&SAMLRequest=abc"))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	if !shouldResumeSAMLLogin("/login", request) {
		t.Fatal("expected login POST with SAMLRequest to resume SAML flow")
	}
}

func TestShouldResumeSAMLLoginSkipsOtherRequests(t *testing.T) {
	request := httptest.NewRequest("POST", "http://idp.test/login", strings.NewReader("user=alice"))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	if shouldResumeSAMLLogin("/login", request) {
		t.Fatal("expected login POST without SAMLRequest to skip SAML resume")
	}
}
