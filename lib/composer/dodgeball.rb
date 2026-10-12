# frozen_string_literal: true

module Composer
  # Backward compatibility wrapper for Dodgeball naming
  class DodgeballClient < ComposerClient
    # Inherits all methods from ComposerClient
    # This provides backward compatibility for code using the Dodgeball name
  end
end
