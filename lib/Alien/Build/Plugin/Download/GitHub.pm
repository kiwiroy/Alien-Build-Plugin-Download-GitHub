package Alien::Build::Plugin::Download::GitHub;

use strict;
use warnings;
use 5.008001;
use Carp qw( croak );
use Path::Tiny qw( path );
use JSON::PP qw( decode_json );
use Alien::Build::Plugin;
use Alien::Build::Plugin::Download::Negotiate;
use Alien::Build::Plugin::Extract::Negotiate;

# ABSTRACT: Alien::Build plugin to download from GitHub
# VERSION

=head1 SYNOPSIS

 use alienfile;

 ...

 share {
 
   plugin 'Download::GitHub' => (
     github_user => 'Perl5-Alien',
     github_repo => 'dontpanic',
     token => '...'
   );
 
 };

=head1 DESCRIPTION

This plugin will download releases from GitHub.  It is generally preferred over
L<Alien::Build::Plugin::Download::Git> for packages that are released on GitHub,
as it has much fewer dependencies and is more reliable.

=head1 PROPERTIES

=head2 github_user

The GitHub user or org that owns the repository.  This property is required.

=head2 github_repo

The GitHub repository name.  This property is required.

=head2 token

A GitHub personal access token (PAT) obtained from L<https://github.com/settings/tokens>.
This is required to increase rate limit of API from 60 to 5000 per hour. The
default is the value of the C<GITHUB_PAT> environment variable. No scopes are
required so ensure all scopes are unset when creating a token. 

See L<https://developer.github.com/v3/#rate-limiting>

=head2 version

Regular expression that can be used to extract a version from a GitHub tag.  The
default ( C<qr/^v?(.*)$/> ) is reasonable for many GitHub repositories.

=head2 prefer

How to sort candidates for selection.  This should be one of three types of values:

=over 4

=item code reference

This will be used as the prefer hook.

=item true value (not code reference)

Use L<Alien::Build::Plugin::Prefer::SortVersions>.

=item false value

Don't set any preference at all.  The order returned from GitHub will be used if
no other prefer plugins are specified.  This may be reasonable for at least some
GitHub repositories.  This is the default.

=back

=cut

has github_user => sub { croak("github_user is required") };
has github_repo => sub { croak("github_repo is required") };
has token => $ENV{GITHUB_PAT};
has version => qr/^v?(.*)$/;
has prefer => 0;

sub init
{
  my($self, $meta) = @_;

  if(defined $meta->prop->{start_url})
  {
    croak("Don't set set a start_url with the Download::GitHub plugin");
  }

  $meta->prop->{start_url} ||= "https://api.github.com/repos/@{[ $self->github_user ]}/@{[ $self->github_repo ]}/releases?access_token=@{[ $self->token ]}";

  $meta->apply_plugin('Download',
    prefer  => $self->prefer,
    version => $self->version,
  );
  $meta->apply_plugin('Extract',
    format  => 'tar.gz',
  );

  $meta->around_hook(
    fetch => sub {
      my $orig = shift;
      my($build, $url) = @_;
      my $res = $orig->($build, $url);
      if($res->{type} eq 'file' && $res->{filename} eq 'releases')
      {
        my $rel;
        if($res->{content})
        {
          $rel = decode_json $res->{content};
        }
        elsif($res->{path})
        {
          $rel = decode_json path($res->{path})->slurp_utf8;
        }
        else
        {
          croak("malformed response object: no content or path");
        }
        return {
          type => 'list',
          list => [
            map {
              my $release = $_;
              my($version) = $release->{tag_name} =~ $self->version;
              my %h = (
                filename => $release->{tag_name},
                url      => $release->{tarball_url},
                defined $version ? (version  => $version) : (),
              );
              \%h;
            } @$rel
          ],
        };
      }
      else
      {
        return $res;
      }
    },
  );

  unless($self->prefer)
  {
    $meta->default_hook(
      prefer => sub {
        my($build, $res) = @_;
        $res;
      },
    );
  }

}

1;

=head1 CAVEATS

The GitHub API is rate limited.  The unauthenticated API is especially so.  This may
render this plugin inoperative for a short time after only a little testing.  Please see

L<https://github.com/Perl5-Alien/Alien-Build-Plugin-Download-GitHub/issues/3>

=cut
