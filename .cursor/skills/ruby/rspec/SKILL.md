---
name: rspec
description: RSpec and Rails testing best practices from Better Specs. Use when writing or reviewing RSpec specs, request specs, model specs, or integration tests in Ruby/Rails projects.
---

# RSpec & Better Specs

This skill applies [Better Specs](https://www.betterspecs.org/) guidelines: Rails testing best practices for clear, maintainable RSpec specs.

Use when writing or reviewing RSpec examples, request specs, model specs, or integration tests.

## Describe Your Methods

Be explicit about what you are describing. Use the Ruby documentation convention: **`.`** (or `::`) for class methods, **`#`** for instance methods.

```ruby
# BAD
describe 'the authenticate method for User' do
describe 'if the user is an admin' do

# GOOD
describe '.authenticate' do
describe '#admin?' do
```

## Use Contexts

Use `context` to group examples. Start context descriptions with **when**, **with**, or **without**.

```ruby
# BAD
it 'has 200 status code if logged in' do
  expect(response).to respond_with 200
end
it 'has 401 status code if not logged in' do
  expect(response).to respond_with 401
end

# GOOD
context 'when logged in' do
  it { is_expected.to respond_with 200 }
end
context 'when logged out' do
  it { is_expected.to respond_with 401 }
end
```

## Keep Descriptions Short

A spec description should stay under ~40 characters. Split with contexts and use `is_expected` where it helps.

```ruby
# BAD
it 'has 422 status code if an unexpected params will be added' do

# GOOD
context 'when not valid' do
  it { is_expected.to respond_with 422 }
end
```

## Single Expectation (Isolated Unit Specs)

In isolated unit specs, prefer **one assertion per example**. Multiple expectations often mean multiple behaviors.

```ruby
# GOOD (isolated)
it { is_expected.to respond_with_content_type(:json) }
it { is_expected.to assign_to(:resource) }
```

In **non-isolated** tests (DB, HTTP, integration), multiple expectations in one example are acceptable to avoid repeating heavy setup.

```ruby
# GOOD (not isolated)
it 'creates a resource' do
  expect(response).to respond_with_content_type(:json)
  expect(response).to assign_to(:resource)
end
```

## Test All Possible Cases

Cover **valid**, **edge**, and **invalid** cases. Think through all meaningful inputs and outcomes.

```ruby
# BAD
it 'shows the resource'

# GOOD
describe '#destroy' do
  context 'when resource is found' do
    it 'responds with 200'
    it 'shows the resource'
  end
  context 'when resource is not found' do
    it 'responds with 404'
  end
  context 'when resource is not owned' do
    it 'responds with 404'
  end
end
```

## Expect vs Should

Use the **`expect`** syntax only. Do not use `should`.

```ruby
# BAD
it 'creates a resource' do
  response.should respond_with_content_type(:json)
end

# GOOD
it 'creates a resource' do
  expect(response).to respond_with_content_type(:json)
end
```

For one-line expectations with implicit subject, use **`is_expected.to`**:

```ruby
# BAD
context 'when not valid' do
  it { should respond_with 422 }
end

# GOOD
context 'when not valid' do
  it { is_expected.to respond_with 422 }
end
```

Configure RSpec to enforce the expect syntax:

```ruby
# spec_helper.rb or rails_helper.rb
RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
```

## Use subject

Use `subject { }` to DRY repeated setup when several examples target the same subject.

```ruby
# BAD
it { expect(assigns('message')).to match(/it was born in Belville/) }

# GOOD
subject { assigns('message') }
it { is_expected.to match(/it was born in Billville/) }
```

Named subject when you need to reference it:

```ruby
subject(:hero) { Hero.first }
it "carries a sword" do
  expect(hero.equipment).to include "sword"
end
```

## Use let and let!

Prefer **`let`** over `before { @var = ... }`. `let` is lazy and cached per example.

```ruby
# BAD
describe '#type_id' do
  before { @resource = FactoryBot.create :device }
  before { @type = Type.find @resource.type_id }
  it 'sets the type_id field' do
    expect(@resource.type_id).to eq(@type.id)
  end
end

# GOOD
describe '#type_id' do
  let(:resource) { FactoryBot.create :device }
  let(:type)     { Type.find resource.type_id }
  it 'sets the type_id field' do
    expect(resource.type_id).to eq(type.id)
  end
end
```

Use **`let!`** when the value must be created before the example runs (e.g. to test queries or scopes).

## Mock or Not to Mock

Prefer testing **real behavior** when possible. Use mocks to isolate external dependencies (DB, HTTP, etc.), not to replace every collaborator.

```ruby
# Example: stub only when simulating a specific scenario
context "when not found" do
  before do
    allow(Resource).to receive(:where).with(created_from: params[:id]).and_return(false)
  end
  it { is_expected.to respond_with 404 }
end
```

## Create Only the Data You Need

Avoid loading or creating more data than the example needs. If you think you need dozens of records, question the design of the test or the code.

```ruby
# GOOD
describe ".top" do
  before { FactoryBot.create_list(:user, 3) }
  it { expect(User.top(2)).to have(2).items }
end
```

## Use Factories, Not Fixtures

Use **Factory Bot** (or similar) instead of fixtures. Factories are easier to control and keep specs readable.

```ruby
# BAD
user = User.create(name: 'Genoveffa', surname: 'Piccolina', city: 'Billyville', ...)

# GOOD
user = FactoryBot.create :user
```

For pure unit tests, prefer objects built in the spec or minimal factories over large factory graphs.

## Easy-to-Read Matchers

Use clear matchers and standard RSpec form.

```ruby
# BAD
lambda { model.save! }.to raise_error Mongoid::Errors::DocumentNotFound

# GOOD
expect { model.save! }.to raise_error(Mongoid::Errors::DocumentNotFound)
```

## Shared Examples

Use **shared examples** to DRY repeated behavior (e.g. across controllers or resources).

```ruby
# GOOD
describe 'GET /devices' do
  let!(:resource) { FactoryBot.create :device, created_from: user.id }
  let!(:uri)      { '/devices' }

  it_behaves_like 'a listable resource'
  it_behaves_like 'a paginable resource'
  it_behaves_like 'a searchable resource'
end
```

## Test What You See

Focus on **models and application behavior** (integration/request specs). Prefer integration tests over controller specs when they give the same confidence. Test behavior and outcomes, not implementation.

## Don't Use "should" in Descriptions

Describe behavior in third person, present tense. Do not start examples with "should".

```ruby
# BAD
it 'should not change timings' do
  consumption.occur_at.should == valid.occur_at
end

# GOOD
it 'does not change timings' do
  expect(consumption.occur_at).to eq(valid.occur_at)
end
```

## Stubbing HTTP

Stub external HTTP in specs (e.g. with **WebMock** or **VCR**) so specs are fast and deterministic.

```ruby
context "with unauthorized access" do
  let(:uri) { 'http://api.example.com/types' }
  before    { stub_request(:get, uri).to_return(status: 401, body: fixture('401.json')) }

  it "gets a not authorized notification" do
    page.driver.get uri
    expect(page).to have_content 'Access denied'
  end
end
```

## Summary Checklist

- [ ] Describe with `.method` or `#method`
- [ ] Use `context 'when/with/without ...'`
- [ ] Short descriptions; split with context
- [ ] One expectation per example in unit specs
- [ ] Cover valid, edge, and invalid cases
- [ ] Use `expect` only; never `should`
- [ ] Use `subject`, `let`, `let!` appropriately
- [ ] Prefer real behavior; mock external deps only
- [ ] Create minimal data; use factories, not fixtures
- [ ] Use shared examples to DRY
- [ ] No "should" in example descriptions

## Reference

[RSpec](https://rspec.info/) · [Better Specs](https://www.betterspecs.org/) — Rails testing best practices from Lelylan Labs.
