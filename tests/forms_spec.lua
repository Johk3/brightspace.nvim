local forms = require("brightspace.auth.forms")

describe("forms.parse", function()
  it("parses tudelft login form", function()
    local html = [[<form id="f" action="https://login.tudelft.nl/sso/module.php/core/loginuserpass?AuthState=_abc%3Ax&amp;y=1" method="post"><input id="username" type="text" name="username" value=""><input type="password" name="password"></form>]]
    local list = forms.parse(html, "https://login.tudelft.nl/")
    assert.equals(1, #list)
    assert.equals("f", list[1].id)
    assert.equals("POST", list[1].method)
    assert.equals("https://login.tudelft.nl/sso/module.php/core/loginuserpass?AuthState=_abc%3Ax&y=1", list[1].action)
    assert.equals("", list[1].inputs.username)
  end)

  it("parses saml auto-post form", function()
    local html = [[<form method="post" action="https://engine.surfconext.nl/authentication/sp/consume-assertion"><input type="hidden" name="SAMLResponse" value="PHNhbWw+"/><input type="hidden" name="RelayState" value="r&amp;s"/></form>]]
    local list = forms.parse(html, "https://engine.surfconext.nl/")
    assert.equals(1, #list)
    assert.equals("PHNhbWw+", list[1].inputs.SAMLResponse)
    assert.equals("r&s", list[1].inputs.RelayState)
  end)

  it("resolves relative action", function()
    local html = [[<form action="/d2l/lp/auth/login/samlLogin.d2l" method="post"></form>]]
    local list = forms.parse(html, "https://brightspace.tudelft.nl/x")
    assert.equals("https://brightspace.tudelft.nl/d2l/lp/auth/login/samlLogin.d2l", list[1].action)
  end)

  it("handles single quotes and attribute order", function()
    local html = [[<FORM method='get' action='/a'><input value='v' name='n' type='hidden'></FORM>]]
    local list = forms.parse(html, "https://h.example/")
    assert.equals("GET", list[1].method)
    assert.equals("v", list[1].inputs.n)
  end)

  it("decodes numeric entities", function()
    local html = [[<form action="/a&#x2F;b&#47;c" method="post"><input name="q" value="&quot;x&quot;"></form>]]
    local list = forms.parse(html, "https://h.example/")
    assert.equals("https://h.example/a/b/c", list[1].action)
    assert.equals('"x"', list[1].inputs.q)
  end)
end)

describe("forms.find", function()
  it("finds by predicate", function()
    local list = forms.parse([[<form id="a" action="/1"></form><form id="b" action="/2"><input name="z" value="1"></form>]], "https://h.example/")
    assert.equals("b", forms.find(list, function(f) return f.inputs.z ~= nil end).id)
    assert.is_nil(forms.find(list, function(f) return f.id == "nope" end))
  end)
end)
