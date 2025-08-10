# Publishing Chainex to Hex.pm

This guide walks you through publishing the Chainex library to Hex.pm, the package manager for the Elixir ecosystem.

## Prerequisites

### 1. Create a Hex.pm Account

If you don't have a Hex.pm account yet:

1. Go to https://hex.pm
2. Click "Sign up" 
3. Fill in your username, email, and password
4. Verify your email address

### 2. Authenticate with Hex

Run the following command and enter your Hex.pm credentials:

```bash
mix hex.user auth
```

This will store your API key locally for publishing packages.

### 3. Update Package Metadata

Edit `mix.exs` and update the following fields with your information:

```elixir
# In mix.exs, update these fields:
maintainers: ["Your Name"],  # Replace with your name
links: %{
  "GitHub" => "https://github.com/YOUR_USERNAME/chainex",  # Your GitHub repo
  "Documentation" => "https://hexdocs.pm/chainex"
}
```

Also update the LICENSE file with your name and year.

## Pre-Publishing Checklist

### 1. Run All Tests

Ensure all tests pass:

```bash
# Run unit tests
mix test

# Run integration tests (requires API keys)
mix test.integration

# Run all tests
mix test.all
```

### 2. Check for Warnings

```bash
# Format code
mix format

# Run dialyzer for type checking
mix dialyzer

# Check for compilation warnings
mix compile --warnings-as-errors
```

### 3. Verify Documentation

```bash
# Generate docs locally and review
mix docs
open doc/index.html
```

### 4. Check Package Contents

Review what will be included in the package:

```bash
mix hex.build
```

This creates a `.tar` file. You can inspect it with:

```bash
tar -tzf chainex-0.1.0.tar
```

### 5. Audit Dependencies

Check for security vulnerabilities:

```bash
mix hex.audit
```

## Publishing Your Package

### First-Time Publishing

1. **Dry run** (recommended - simulates publishing without actually doing it):

```bash
mix hex.publish --dry-run
```

2. **Review the output** carefully:
   - Check that all files are included
   - Verify the version number
   - Ensure metadata is correct

3. **Publish to Hex.pm**:

```bash
mix hex.publish
```

You'll be prompted to confirm. Type `Y` to proceed.

4. **Publish documentation** to HexDocs:

```bash
mix hex.publish docs
```

### Publishing Updates

When releasing new versions:

1. **Update version** in `mix.exs`:

```elixir
version: "0.2.0",  # Increment according to semver
```

2. **Update CHANGELOG.md** with the new version and changes

3. **Commit all changes**:

```bash
git add .
git commit -m "Release v0.2.0"
git tag v0.2.0
git push origin main --tags
```

4. **Publish the new version**:

```bash
mix hex.publish
```

## Post-Publishing

### Verify Your Package

1. Visit https://hex.pm/packages/chainex
2. Check that all information displays correctly
3. Visit https://hexdocs.pm/chainex to verify documentation

### Retire Versions (if needed)

If you need to retire a broken version:

```bash
mix hex.retire chainex 0.1.0 security "Security issue discovered"
```

Reasons can be: `renamed`, `deprecated`, `security`, `invalid`, or `other`.

### Managing Owners

Add additional maintainers:

```bash
mix hex.owner add chainex other_username
```

## Semantic Versioning

Follow semantic versioning (https://semver.org/):

- **MAJOR** (1.0.0): Breaking API changes
- **MINOR** (0.2.0): New features, backwards compatible
- **PATCH** (0.1.1): Bug fixes, backwards compatible

## Common Issues and Solutions

### Issue: "Package name already taken"

**Solution**: Choose a different name in `mix.exs`:

```elixir
package: [
  name: "chainex_llm",  # Alternative name
  ...
]
```

### Issue: "Invalid version requirement"

**Solution**: Ensure all dependencies use proper version specs:

```elixir
{:req, "~> 0.4.0"},  # Good
{:req, ">= 0.4.0"},  # Also good
{:req, "*"},         # Bad - too loose
```

### Issue: Documentation not building

**Solution**: Ensure ExDoc is in your dependencies:

```elixir
{:ex_doc, "~> 0.31", only: :dev, runtime: false}
```

### Issue: Missing required fields

**Solution**: Ensure all required package fields are present:

```elixir
package: [
  description: "...",  # Required
  licenses: ["MIT"],   # Required
  links: %{...},       # Recommended
  files: [...]         # Optional but recommended
]
```

## Best Practices

1. **Test on multiple Elixir/OTP versions** before publishing
2. **Include comprehensive documentation** with examples
3. **Add badges** to your README:

```markdown
[![Hex.pm](https://img.shields.io/hexpm/v/chainex.svg)](https://hex.pm/packages/chainex)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/chainex)
[![License](https://img.shields.io/hexpm/l/chainex.svg)](https://github.com/your-username/chainex/blob/main/LICENSE)
```

4. **Set up CI/CD** (GitHub Actions, CircleCI, etc.)
5. **Respond to issues** and maintain your package

## Resources

- [Hex.pm Documentation](https://hex.pm/docs/publish)
- [HexDocs Documentation](https://hexdocs.pm)
- [Elixir Library Guidelines](https://hexdocs.pm/elixir/library-guidelines.html)
- [Semantic Versioning](https://semver.org/)

## Support

If you encounter issues:

1. Check the [Hex.pm FAQ](https://hex.pm/docs/faq)
2. Ask on [Elixir Forum](https://elixirforum.com/)
3. Join the [Elixir Slack](https://elixir-slackin.herokuapp.com/)

---

Remember: Once published, packages cannot be unpublished (only retired), so double-check everything before publishing!