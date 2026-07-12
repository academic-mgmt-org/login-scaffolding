<?php

namespace App\Providers;

use App\Contracts\GatewayClient;
use App\Exceptions\GatewayRpcException;
/* @chisel-registration */
use App\Actions\Fortify\CreateNewUser;
/* @end-chisel-registration */
use App\Actions\Fortify\ResetUserPassword;
use App\Models\User;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Laravel\Fortify\Fortify;

class FortifyServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        $this->configureActions();
        $this->configureGatewayAuthentication();
        $this->configureViews();
        $this->configureRateLimiting();
    }

    /**
     * Replace Fortify's local password check with the external gRPC gateway.
     */
    private function configureGatewayAuthentication(): void
    {
        Fortify::authenticateUsing(function (Request $request): ?User {
            try {
                $login = app(GatewayClient::class)->login(
                    (string) $request->input(Fortify::username()),
                    (string) $request->input('password'),
                );
            } catch (GatewayRpcException $exception) {
                if ($exception->isUnauthenticated()) {
                    return null;
                }

                report($exception);

                throw ValidationException::withMessages([
                    Fortify::username() => 'El gateway de autenticación no está disponible.',
                ]);
            }

            $email = Str::lower((string) $request->input(Fortify::username()));
            $user = User::query()->firstOrNew(['email' => $email]);
            $attributes = [
                'name' => $user->name ?: Str::headline(Str::before($email, '@')),
                'email_verified_at' => $user->email_verified_at ?: now(),
            ];

            if (! $user->exists) {
                $attributes['password'] = Str::password(64);
            }

            $user->forceFill($attributes)->save();

            $request->session()->put('gateway_auth', [
                'access_token' => $login['access_token'],
                'refresh_token' => $login['refresh_token'],
                'session_id' => $login['session_id'],
                'expires_at' => now()->addSeconds(max(0, $login['expires_in']))->toIso8601String(),
            ]);

            return $user;
        });
    }

    /**
     * Configure Fortify actions.
     */
    private function configureActions(): void
    {
        Fortify::resetUserPasswordsUsing(ResetUserPassword::class);
        /* @chisel-registration */
        Fortify::createUsersUsing(CreateNewUser::class);
        /* @end-chisel-registration */
    }

    /**
     * Configure Fortify views.
     */
    private function configureViews(): void
    {
        Fortify::loginView(fn () => view('pages::auth.login'));
        /* @chisel-email-verification */
        Fortify::verifyEmailView(fn () => view('pages::auth.verify-email'));
        /* @end-chisel-email-verification */
        /* @chisel-2fa */
        Fortify::twoFactorChallengeView(fn () => view('pages::auth.two-factor-challenge'));
        /* @end-chisel-2fa */
        /* @chisel-password-confirmation */
        Fortify::confirmPasswordView(fn () => view('pages::auth.confirm-password'));
        /* @end-chisel-password-confirmation */
        /* @chisel-registration */
        Fortify::registerView(fn () => view('pages::auth.register'));
        /* @end-chisel-registration */
        Fortify::resetPasswordView(fn () => view('pages::auth.reset-password'));
        Fortify::requestPasswordResetLinkView(fn () => view('pages::auth.forgot-password'));
    }

    /**
     * Configure rate limiting.
     */
    private function configureRateLimiting(): void
    {
        RateLimiter::for('two-factor', function (Request $request) {
            return Limit::perMinute(5)->by($request->session()->get('login.id'));
        });

        RateLimiter::for('login', function (Request $request) {
            $throttleKey = Str::transliterate(Str::lower($request->input(Fortify::username())).'|'.$request->ip());

            return Limit::perMinute(5)->by($throttleKey);
        });

        /* @chisel-passkeys */
        RateLimiter::for('passkeys', function (Request $request) {
            $credentialId = $request->input('credential.id');

            return Limit::perMinute(10)->by(
                ($credentialId ?: $request->session()->getId()).'|'.$request->ip(),
            );
        });
        /* @end-chisel-passkeys */
    }
}
