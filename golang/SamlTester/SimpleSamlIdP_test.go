package main

import (
	"github.com/crewjam/saml"
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
	if roles.FriendlyName != "Roles" {
		t.Fatalf("expected Roles friendly name, got %q", roles.FriendlyName)
	}
	if roles.Name != "Roles" {
		t.Fatalf("expected Roles attribute name, got %q", roles.Name)
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
