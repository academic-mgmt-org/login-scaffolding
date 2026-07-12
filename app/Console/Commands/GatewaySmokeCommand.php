<?php

namespace App\Console\Commands;

use App\Contracts\GatewayClient;
use App\Exceptions\GatewayRpcException;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;
use RuntimeException;
use Throwable;

#[Signature('gateway:smoke {--username= : Usuario del gateway} {--no-prompt : No solicitar datos faltantes}')]
#[Description('Ejecuta login, consultas, logout y pruebas negativas contra el gateway gRPC')]
class GatewaySmokeCommand extends Command
{
    /**
     * Execute the console command.
     */
    public function handle(GatewayClient $gateway): int
    {
        $username = trim((string) ($this->option('username') ?: config('gateway.smoke.username')));
        $password = (string) config('gateway.smoke.password');

        if ($username === '' && ! $this->option('no-prompt')) {
            $username = trim((string) $this->ask('Usuario'));
        }

        if ($password === '' && ! $this->option('no-prompt')) {
            $password = (string) $this->secret('Contraseña');
        }

        if ($username === '' || $password === '') {
            $this->error('Define las credenciales por entorno o entrada interactiva.');

            return self::FAILURE;
        }

        $accessToken = null;
        $refreshToken = null;
        $loggedOut = false;

        try {
            $this->line('1/8 Rechazo sin Authorization');
            try {
                $gateway->recentNotifications(null, 1);
                throw new RuntimeException('El gateway aceptó notificaciones sin Authorization.');
            } catch (GatewayRpcException $exception) {
                if (! $exception->isUnauthenticated()) {
                    throw $exception;
                }
            }
            $this->info('OK');

            $this->line('2/8 Login por auth.v1.AuthService/Login');
            $login = $gateway->login($username, $password);
            $accessToken = $login['access_token'];
            $refreshToken = $login['refresh_token'];
            $this->info('OK');

            $this->line('3/8 Contador de no leídas');
            $unreadCount = $gateway->countUnread($accessToken);
            if ($unreadCount < 0) {
                throw new RuntimeException('CountUnread devolvió un valor inválido.');
            }
            $this->info('OK');

            if ($unreadCount > 0) {
                $this->line('4/8 Listado de no leídas');
                $gateway->listUnread($accessToken, $unreadCount);
                $this->info('OK');
            } else {
                $this->line('4/8 No hay notificaciones no leídas; se omite el listado.');
            }

            $this->line('5/8 Notificaciones recientes');
            $recent = $gateway->recentNotifications($accessToken, 5);
            $this->info('OK');

            $this->line('6/8 Logout y revocación remota');
            if (! $gateway->logout($accessToken, $refreshToken)['success']) {
                throw new RuntimeException('Logout no confirmó el cierre.');
            }
            $loggedOut = true;
            $this->info('OK');

            $this->line('7/8 ValidateToken devuelve false');
            if ($gateway->validateToken($accessToken)) {
                throw new RuntimeException('El token continuó válido después de logout.');
            }
            $this->info('OK');

            $this->line('8/8 Rechazo del token revocado');
            try {
                $gateway->recentNotifications($accessToken, 1);
                throw new RuntimeException('El token revocado todavía accedió a notificaciones.');
            } catch (GatewayRpcException $exception) {
                if (! $exception->isUnauthenticated()) {
                    throw $exception;
                }
            }
            $this->info('OK');

            $this->newLine();
            $this->info("Flujo completo OK. No leídas: {$unreadCount}; recientes: ".count($recent).'.');

            return self::SUCCESS;
        } catch (Throwable $exception) {
            $this->newLine();
            $this->error($exception->getMessage());

            return self::FAILURE;
        } finally {
            if ($accessToken !== null && $refreshToken !== null && ! $loggedOut) {
                try {
                    $gateway->logout($accessToken, $refreshToken);
                    $this->warn('La sesión de prueba se cerró durante la limpieza.');
                } catch (Throwable) {
                    $this->warn('No se pudo cerrar la sesión de prueba; revise el gateway.');
                }
            }
        }
    }
}
