{
  description = "A Nix-flake-based R package development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  inputs.rNvim = {
    url = "github:R-nvim/R.nvim";
    flake = false;
  };

  outputs =
    { self, ... }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import inputs.nixpkgs {
              inherit system;
              config.allowBroken = true;
              overlays = [ inputs.self.overlays.default ];
            };
          }
        );
    in
    {
      overlays.default = final: prev: rec {
        # ==============================================================================
        # SECTION 1: YOUR PACKAGE'S DEPENDENCIES (from DESCRIPTION file)
        # ==============================================================================
        # These are the packages YOUR package needs to run (Imports field)
        # Replace 'cli' with your actual package dependencies
        runtimeDeps = with final.rPackages; [
          cli
          # Add more packages from your DESCRIPTION Imports: section here
          # Example: httr, jsonlite, dplyr, etc.
        ];

        # If you need packages from GitHub (not on CRAN), add them here
        # You'll need to define inputs at the top and build them in Section 2
        githubDataDeps = [
          # Example: myGithubPackage
        ];

        # ==============================================================================
        # SECTION 2: BUILD SPECIAL PACKAGES (from GitHub, not from CRAN)
        # ==============================================================================
        # These packages aren't on CRAN, so we build them from source

        # Build nvimcom manually from R.nvim source
        nvimcom = final.rPackages.buildRPackage {
          name = "nvimcom";
          src = inputs.rNvim;
          sourceRoot = "source/nvimcom";

          buildInputs = with final; [
            R
            gcc
            gnumake
            qpdf
          ];

          meta = {
            description = "R.nvim communication package";
            homepage = "https://github.com/R-nvim/R.nvim";
            maintainers = [ ];
          };
        };

        # Add custom GitHub package builds here
        # There are two patterns you can use:

        # PATTERN A: Using flake inputs (preferred - rev/sha locked in flake.lock)
        # 1. Add to inputs at top of file:
        #    inputs.myGithubPackage = { url = "github:owner/repo"; flake = false; };
        # 2. Build it here:
        # myGithubPackage = final.rPackages.buildRPackage {
        #   name = "myGithubPackage";
        #   src = inputs.myGithubPackage;
        #   propagatedBuildInputs = with final.rPackages; [ dependency1 dependency2 ];
        # };

        # PATTERN B: Using fetchFromGitHub (rev/sha specified here)
        # myGithubPackage = final.rPackages.buildRPackage {
        #   name = "myGithubPackage";
        #   src = final.fetchFromGitHub {
        #     owner = "owner";
        #     repo = "repo";
        #     rev = "commit-hash";
        #     sha256 = "sha256-...";
        #   };
        #   propagatedBuildInputs = with final.rPackages; [ dependency1 dependency2 ];
        # };

        # ==============================================================================
        # SECTION 3: BUILD YOUR PACKAGE
        # ==============================================================================
        # Uncomment and customize this section when you're ready to build your package
        # myRPackage = final.rPackages.buildRPackage {
        #   name = "myRPackage";
        #   src = ./.;
        #   # Give it the runtime dependencies from Section 1
        #   propagatedBuildInputs = runtimeDeps ++ githubDataDeps;
        # };

        # ==============================================================================
        # SECTION 4: DEVELOPMENT ENVIRONMENT PACKAGES
        # ==============================================================================
        # All the packages you want available when developing
        # This is SEPARATE from your package's runtime dependencies!

        devPackages = with final.rPackages; [
          # Development tools
          devtools
          roxygen2
          testthat
          usethis
          pkgdown
          rcmdcheck
          pak
          urlchecker

          # Editor support (nvim, LSP, etc.)
          languageserver
          nvimcom
          httpgd
          lintr
          cyclocomp

          # Useful utilities
          tibble
          cli
          fs

          # Uncomment if your package has vignettes
          # knitr
          # rmarkdown

          # Add suggested packages from your DESCRIPTION Suggests: section here
          # Example: ggplot2, tidyr, dplyr, etc.
        ];

        # Combine: your package's dependencies + development tools
        # This is what goes into your R environment
        allPackages = runtimeDeps ++ githubDataDeps ++ devPackages;

        # ==============================================================================
        # SECTION 5: WRAP R AND RADIAN WITH ALL PACKAGES
        # ==============================================================================
        # Create rWrapper with packages (for LSP and R.nvim)
        baseWrappedR = final.rWrapper.override { packages = allPackages; };

        # Wrap R with R_QPDF environment variable
        wrappedR = final.symlinkJoin {
          name = "wrapped-r-with-qpdf";
          paths = [ baseWrappedR ];
          buildInputs = [ final.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/R \
              --set R_QPDF "${final.qpdf}/bin/qpdf"
            wrapProgram $out/bin/Rscript \
              --set R_QPDF "${final.qpdf}/bin/qpdf"
          '';
        };

        # Create radianWrapper with same packages (for interactive use)
        baseWrappedRadian = final.radianWrapper.override { packages = allPackages; };

        # Wrap radian with R_QPDF environment variable
        wrappedRadian = final.symlinkJoin {
          name = "wrapped-radian-with-qpdf";
          paths = [ baseWrappedRadian ];
          buildInputs = [ final.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/radian \
              --set R_QPDF "${final.qpdf}/bin/qpdf"
          '';
        };
      };

      devShells = forEachSupportedSystem (
        { pkgs }:
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              wrappedR # R with packages for LSP
              wrappedRadian # radian with packages for interactive use
              qpdf # PDF compression checks

              # Additional system tools for package development
              # git           # Version control
              # pandoc        # Document conversion (for vignettes)
              # quarto        # Modern publishing system
              # html-tidy     # HTML validation for R CMD check
              # (texlive.combine {
              #   inherit (texlive)
              #     scheme-small
              #     inconsolata # Required for PDF manual generation
              #     ;
              # })
            ];

            shellHook = ''
              # Set R_QPDF environment variable for R CMD check
              export R_QPDF="${pkgs.qpdf}/bin/qpdf"

              echo "🔧 R Package Development Environment"
              echo ""
              echo "Quick commands:"
              echo "  devtools::load_all()                        - Load package for testing"
              echo "  devtools::test()                            - Run tests"
              echo "  devtools::document()                        - Generate documentation"
              echo "  devtools::check()                           - Run R CMD check"
              echo "  pkgdown::build_site()                       - Build package website"
              echo "  urlchecker::url_check()                     - Check URLs in documentation"
              echo "  revdepcheck::revdep_check(num_workers = 4)  - Check reverse dependencies"
              echo ""
              echo "Start R with: radian"
            '';
          };
        }
      );

      templates = {
        default = {
          path = ./.;
          description = "R package development environment with nvimcom and R.nvim integration";
          welcomeText = ''
            # R Package Development Template

            ## Getting started
            1. Edit flake.nix Section 1: Add your DESCRIPTION Imports to runtimeDeps
            2. Edit flake.nix Section 4: Add your DESCRIPTION Suggests to devPackages
            3. Uncomment Section 3 to build your package
            4. Run `direnv allow` (if using direnv) or `nix develop`

            ## What's included
            - R with devtools, roxygen2, testthat, usethis, pak, and pkgdown
            - languageserver and nvimcom for editor integration
            - radian (modern R console)
            - Clear 5-section structure with helpful comments
          '';
        };
      };
    };
}
