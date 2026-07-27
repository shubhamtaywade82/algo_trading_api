# frozen_string_literal: true

# `expect { ... }.to change(X, :count).by(0)` reads as "it changed by zero";
# `not_change` says what is actually meant and composes with `.and`, which is
# how idempotency is asserted across several tables at once.
RSpec::Matchers.define_negated_matcher :not_change, :change
