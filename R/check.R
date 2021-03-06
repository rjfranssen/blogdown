#' Provide diagnostics for a website project
#'
#' The function \code{check_site()} runs a series of checks against a website
#' project (see \sQuote{Details}).
#' @export
check_site = function() in_root({
  check_init('Running a series of automated checks for your blogdown website project...')

  message(hrule())
  check_success('A successful check looks like this.')
  check_todo('A check that needs your attention looks like this.')
  check_progress("Let's check out your blogdown site!")
  message(hrule())

  opts$set(check_site = TRUE); on.exit(opts$set(check_site = NULL), add = TRUE)

  check_config()
  check_gitignore()
  check_hugo()
  check_netlify()
  check_content()
})


#' @details \code{check_config()} checks the configuration file
#'   (\file{config.yaml} or \file{config.toml}) for settings such as
#'   \code{baseURL} and \code{ignoreFiles}.
#' @rdname check_site
#' @export
check_config = function() {
  config = load_config()
  f = find_config()
  check_init('Checking ', f)
  open_file(f)

  check_progress('Checking "baseURL" setting for Hugo...')
  base = index_ci(config, 'baseurl')
  if (is_example_url(base)) {
    check_todo('Set "baseURL" to "/" if you do not yet have a domain.')
  } else if (identical(base, '/')) {
    check_todo('Update "baseURL" to your actual URL when ready to publish.')
  } else {
    check_success('Found baseURL = "', base, '"; nothing to do here!')
  }

  check_progress('Checking "ignoreFiles" setting for Hugo...')
  ignore = c('\\.Rmd$', '\\.Rmarkdown$', '_cache$', '\\.knit\\.md$', '\\.utf8\\.md$')
  if (is.null(s <- config[['ignoreFiles']])) {
    check_todo('Set "ignoreFiles" to ', xfun::tojson(ignore))
  } else if (!all(ignore %in% s)) {
    check_todo(
      'Add these items to the "ignoreFiles" setting: ',
      gsub('^\\[|\\]$', '', xfun::tojson(I(setdiff(ignore, s))))
    )
  } else if ('_files$' %in% s) {
    check_todo('Remove "_files$" from "ignoreFiles"')
  } else {
    check_success('"ignoreFiles" looks good - nothing to do here!')
  }

  check_progress("Checking setting for Hugo's Markdown renderer...")
  if (is.null(s <- config$markup$goldmark$renderer$unsafe) && hugo_available('0.60')) {
    h = config$markup$defaultMarkdownHandler
    if (is.null(h) || h == 'goldmark') {
      check_progress("You are using the Markdown renderer 'goldmark'.")
      config_goldmark(f)
    } else if (!is.null(h)) {
      check_progress("You are using the Markdown renderer '", h, "'.")
      check_success('No todos now. If you install a new Hugo version, re-run this check.')
    }
  } else {
    check_success('All set!', if (!is.null(s)) ' Found the "unsafe" setting for goldmark.')
  }
  check_done(f)
}

is_example_url = function(url) {
  is.character(url) && grepl(
    '^https?://(www[.])?(example.(org|com)|replace-this-with-your-hugo-site.com)/?', url
  )
}

#' @details \code{check_gitignore()} checks if necessary files are incorrectly
#'   ignored in GIT.
#' @rdname check_site
#' @export
check_gitignore = function() {
  f = '.gitignore'
  check_init('Checking ', f)
  if (!file_exists(f)) return(check_todo(f, ' was not found. You may want to add this.'))

  x = read_utf8(f)
  check_progress('Checking for items to remove...')
  x1 = c('*.html', '*.md', '*.markdown', 'static', 'config.toml', 'config.yaml')
  if (any(i <- x %in% x1)) check_todo(
    'Remove items from ', f, ': ', paste(x[i], collapse = ', ')
  ) else check_success('Nothing to see here - found no items to remove.')

  check_progress('Checking for items you can safely ignore...')
  x2 = c('.DS_Store', 'Thumbs.db')
  if (any(i <- x %in% x2))
    check_success('Found! You have safely ignored: ', paste(x[i], collapse = ', '))
  x3 = setdiff(x2, x)
  if (length(x3)) check_todo('You can safely add to ', f, ': ', paste(x3, collapse = ', '))

  if (file_exists('netlify.toml')) {
    check_progress('Checking for items to ignore if you build the site on Netlify...')
    x4 = c('public', 'resources')
    if (any(i <- x %in% x4))
      check_success('Found! You have safely ignored: ', paste(x[i], collapse = ', '))
    x5 = setdiff(x4, x)
    if (length(x5)) {
      check_todo(
        'When Netlify builds your site, you can safely add to ', f, ': ',
        paste(x5, collapse = ', ')
      )
    }
  }
  check_done(f)
}

config_goldmark = function(f, silent = FALSE) {
  x = switch(
    xfun::file_ext(f),
    yaml = '
markup:
  goldmark:
    renderer:
      unsafe: true
',
    toml = '
[markup]
  [markup.goldmark]
    [markup.goldmark.renderer]
      unsafe = true
'
  )
  if (is.null(x)) return()
  if (!silent) check_todo(
    'Allow goldmark to render raw HTML by adding this setting to ', f,
    ' (see https://github.com/rstudio/blogdown/issues/447 for more info):\n', x
  )
  if (silent || yes_no("==> Do you want blogdown to set this for you?")) {
    cat(x, file = f, append = TRUE)
  }
}

#' @details \code{check_hugo()} checks possible problems with the Hugo
#'   installation and version.
#' @rdname check_site
#' @export
check_hugo = function() {
  if (generator() != 'hugo') return()
  check_init('Checking Hugo')
  check_progress('Checking Hugo version...')
  # current version and all possible versions of Hugo
  cv = hugo_version()
  av = find_hugo("all", quiet = TRUE)

  # if no Hugo versions are installed
  if ((n <- length(av)) == 0) return(check_todo(
    'Hugo not found - use blogdown::install_hugo() to install.'
  ))

  check_success(sprintf(
    'Found %sHugo. You are using Hugo %s.', if (n > 1) paste(n, 'versions of ') else '', cv
  ))

  check_progress('Checking .Rprofile for Hugo version used by blogdown...')

  # .Rprofile exists + most recent Hugo
  if (!(is.null(sv <- getOption('blogdown.hugo.version')))) {
    check_success(sprintf('blogdown is using Hugo %s to build site locally.', sv))
  } else {
    check_progress('Hugo version not set in .Rprofile.')
    if (!file_exists('.Rprofile'))
      check_todo('Use blogdown::config_Rprofile() to create .Rprofile for the current project.')
    check_todo(sprintf('Set options(blogdown.hugo.version = "%s") in .Rprofile.', cv))
  }

  if (file_exists('netlify.toml') && !isTRUE(opts$get('check_site'))) check_todo(
    'Also run blogdown::check_netlify() to check for possible problems with Hugo and Netlify.'
  )

  check_done('Hugo')
}

#' @details \code{check_netlify()} checks the Hugo version specification and the
#'   publish directory in the Netlify config file \file{netlify.toml}.
#'   Specifically, it will check if the local Hugo version matches the version
#'   specified in \file{netlify.toml} (in the environment variable
#'   \var{HUGO_VERSION}), and if the \var{publish} setting in
#'   \file{netlify.toml} matches the \var{publishDir} setting in Hugo's config
#'   file (if it is set).
#' @rdname check_site
#' @export
check_netlify = function() {
  check_init('Checking netlify.toml...')
  if (!file.exists(f <- 'netlify.toml')) return(
    check_todo(f, ' was not found. Use blogdown::config_netlify() to create file.')
  )
  cfg = find_config()
  open_file(f)
  x = read_toml(f)
  v = x$context$production$environment$HUGO_VERSION
  v2 = as.character(hugo_version())
  if (is.null(v)) v = x$build$environment$HUGO_VERSION

  if (is.null(v)) {
    check_progress('HUGO_VERSION not found in ', f, '.')
    check_todo('Set HUGO_VERSION = ', v2, ' in [build] context of ', f, '.')
  } else {
    check_success('Found HUGO_VERSION = ', v, ' in [build] context of ', f, '.')
    check_progress('Checking that Netlify & local Hugo versions match...')
    if (v2 == v) {
      check_success(
        "It's a match! Blogdown and Netlify are using the same Hugo version (", v2, ")."
      )
    } else {
      check_progress(
        'Mismatch found:\n',
        '  blogdown is using Hugo version (', v2, ') to build site locally.\n',
        '  Netlify is using Hugo version (', v, ') to build site.'
      )
      check_todo(
        'Option 1: Change HUGO_VERSION = "', v2, '" in ', f, ' to match local version.'
      )
      check_todo(
        'Option 2: Use blogdown::install_hugo("', v, '") to match Netlify version, ',
        'and set options(blogdown.hugo.version = "', v, '") in .Rprofile to pin this Hugo version.'
      )
    }
  }

  check_progress('Checking that Netlify & local Hugo publish directories match...')
  if (!is.null(p1 <- x$build$publish)) {
    p2 = publish_dir(tmp = FALSE, default = NULL)
    if (p3 <- is.null(p2)) p2 = 'public'
    if (!identical(p2, gsub('/$', '', p1))) {
      check_progress(
        'Mismatch found:\n',
        '  The Netlify "publish" directory in "', f, '" is "', p1, '".\n',
        '  The local Hugo "publishDir" directory is "', p2,
        '" (', if (p3) "Hugo's default" else c('as set in ', cfg), ').'
      )
      check_todo('Open ', f, ' and under [build] set publish = "', p2, '".')
    } else {
      check_success('Good to go - blogdown and Netlify are using the same publish directory: ', p2)
    }
  }

  check_done(f)
}

#' @details \code{check_content()} checks for possible problems in the content
#'   files. It searches for posts with future dates and draft posts, and lists
#'   them if found (such posts appear in the local preview by default, but will
#'   be ignored by default when building the site). Then it checks for R
#'   Markdown posts that have not been rendered, or have output files older than
#'   the source files, and plain Markdown posts that have \file{.html} output
#'   files (which they should not have). At last it detects \file{.html} files
#'   that seem to be generated by clicking the Knit button in RStudio with
#'   \pkg{blogdown} < v0.21. Such \file{.html} files should be deleted, since
#'   the Knit button only works with \pkg{blogdown} >= v0.21.
#' @rdname check_site
#' @export
check_content = function() {
  check_init('Checking content files')
  meta = scan_yaml()
  detect = function(field, fun) names(unlist(lapply(
    meta, function(m) fun(m[[field]])
  )))

  check_progress('Checking for previewed content that will not be published...')
  files = detect('date', function(d) tryCatch(
    if (isTRUE(as.Date(d) > Sys.Date())) TRUE, error = function(e) NULL
  ))
  if (length(files)) {
    check_todo(
      'Found ', n <- length(files), ' file', if (n > 1) 's',
      ' with a future publish date:\n\n', indent_list(files), '\n\n',
      "  If you want to publish today, change a file's YAML key to 'date: ",
      format(Sys.Date(), '%Y-%m-%d'), "'"
    )
  } else {
    check_success('Found 0 files with future publish dates.')
  }

  files = detect('draft', function(d) if (isTRUE(d)) TRUE)
  if (length(files)) {
    check_todo(
      'Found ', n <- length(files), ' file', if (n > 1) 's',
      ' marked as drafts:\n\n', indent_list(files), '\n\n',
      "  To un-draft, change a file's YAML from 'draft: true' to 'draft: false'"
    )
  } else {
    check_success('Found 0 files marked as drafts.')
  }

  check_progress('Checking your R Markdown content...')
  rmds = list_rmds()
  if (length(files <- filter_newfile(rmds))) {
    check_todo(
      'Found ', n <- length(files), ' R Markdown file', if (n > 1) 's',
      ' to render:\n\n', indent_list(files), '\n\n',
      "  To render a file, knit or use blogdown::build_site(build_rmd = 'newfile')"
    )
  } else {
    check_success('All R Markdown files have been knitted.')
  }

  files = setdiff(rmds, files)
  files = files[require_rebuild(output_file(files), files)]
  if (length(files)) {
    check_todo(
      'Found ', n <- length(files), ' R Markdown file', if (n > 1) 's',
      ' to update by re-rendering:\n\n', indent_list(files), '\n\n',
      "  To update a file, re-knit or use blogdown::build_site(build_rmd = 'timestamp')"
    )
  } else {
    check_success('All R Markdown output files are up to date with their source files.')
  }

  check_progress('Checking for .html/.md files to clean up...')
  if (n <- length(files <- list_duplicates())) {
    check_todo(
      'Found ', n, ' duplicated plain Markdown and .html output file',
      if (n > 1) 's', ':\n\n', indent_list(files), '\n\n',
      "  To fix, run blogdown::clean_duplicates()."
    )
  } else {
    check_success('Found 0 duplicate .html output files.')
  }
  check_garbage_html()
  check_done('Content')
}

list_duplicates = function() in_root({
  x = with_ext(list_rmds(pattern = '[.](md|markdown)$'), 'html')
  x[file_exists(x)]
})

#' Clean duplicated output files
#'
#' For an output file \file{FOO.html}, \file{FOO.md} should be deleted if
#' \file{FOO.Rmd} exists, and \file{FOO.html} should be deleted when
#' \file{FOO.Rmarkdown} exists (because \file{FOO.Rmarkdown} should generate
#' \file{FOO.markdown} instead) or neither \file{FOO.Rmarkdown} nor
#' \file{FOO.Rmd} exists (because a plain Markdown file should not be knitted to
#' HTML).
#' @param preview Whether to preview the file list, or just delete the files. If
#'   you are sure the files can be safely deleted, use \code{preview = FALSE}.
#' @export
#' @return For \code{preview = TRUE}, a logical vector indicating if each file
#'   was successfully deleted; for \code{preview = FALSE}, the file list is
#'   printed.
clean_duplicates = function(preview = TRUE) in_root({
  x = list_duplicates()
  x1 = with_ext(x, 'Rmd');       i1 = file_exists(x1)
  x2 = with_ext(x, 'Rmarkdown'); i2 = file_exists(x2)
  # if .Rmd exists, delete .md; if .Rmd does not exist or .Rmarkdown exists,
  # delete .html
  x = c(with_ext(x[i1], 'md'), x[i2 | !i1])
  x = x[file_exists(x)]
  if (length(x)) {
    if (preview) msg_cat(
      'Found possibly duplicated output files. Run blogdown::clean_duplicates(preview = FALSE)',
      ' if you are sure they can be deleted:\n\n', indent_list(x), '\n'
    ) else file.remove(x)
  } else {
    msg_cat('No duplicated output files were found.\n')
  }
})

check_garbage_html = function() {
  res = unlist(lapply(list_files(content_file(), '[.]html$'), function(f) {
    if (file.size(f) < 200000) return()
    x = readLines(f, n = 15)
    if (any(x == '<meta name="generator" content="pandoc" />')) return(f)
  }))
  if (n <- length(res)) {
    check_todo(
      'Found ', n, ' incompatible .html file', if (n > 1) 's',
      ' introduced by previous blogdown versions:\n\n', remove_list(res), '\n\n',
      '  To fix, run the above command and then blogdown::build_site(build_rmd = "newfile").'
    )
  } else {
    check_success('Found 0 incompatible .html files to clean up.')
  }
}
