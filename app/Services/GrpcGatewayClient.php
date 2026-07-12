<?php

namespace App\Services;

use App\Contracts\GatewayClient;
use App\Exceptions\GatewayRpcException;
use App\Grpc\Auth\V1\AuthServiceClient;
use App\Grpc\Auth\V1\GenericResponse as AuthGenericResponse;
use App\Grpc\Auth\V1\LoginRequest;
use App\Grpc\Auth\V1\LoginResponse;
use App\Grpc\Auth\V1\LogoutRequest;
use App\Grpc\Auth\V1\ValidateTokenRequest;
use App\Grpc\Auth\V1\ValidateTokenResponse;
use App\Grpc\Notificaciones\V1\CountUnreadRequest;
use App\Grpc\Notificaciones\V1\CountUnreadResponse;
use App\Grpc\Notificaciones\V1\ListNotificationsRequest;
use App\Grpc\Notificaciones\V1\ListNotificationsResponse;
use App\Grpc\Notificaciones\V1\Notification;
use App\Grpc\Notificaciones\V1\NotificationServiceClient;
use Grpc\ChannelCredentials;
use RuntimeException;

class GrpcGatewayClient implements GatewayClient
{
    private AuthServiceClient $auth;

    private NotificationServiceClient $notifications;

    /** @var array{timeout: int} */
    private array $callOptions;

    public function __construct()
    {
        if (! extension_loaded('grpc')) {
            throw new RuntimeException('La extensión grpc de PHP no está instalada. Inicia la aplicación con Laravel Sail.');
        }

        $host = (string) config('gateway.host');
        $options = ['credentials' => ChannelCredentials::createInsecure()];

        $this->auth = new AuthServiceClient($host, $options);
        $this->notifications = new NotificationServiceClient($host, $options);
        $this->callOptions = [
            'timeout' => max(1_000, (int) config('gateway.timeout_ms')) * 1_000,
        ];
    }

    public function login(string $username, string $password): array
    {
        $request = (new LoginRequest)
            ->setUsername($username)
            ->setPassword($password);

        [$response, $status] = $this->auth
            ->Login($request, [], $this->callOptions)
            ->wait();

        $this->assertOk($status, 'auth.v1.AuthService/Login');
        $this->assertResponseType($response, LoginResponse::class, 'auth.v1.AuthService/Login');

        $result = [
            'access_token' => $response->getAccessToken(),
            'refresh_token' => $response->getRefreshToken(),
            'session_id' => $response->getSessionId(),
            'expires_in' => $response->getExpiresIn(),
        ];

        if ($result['access_token'] === '' || $result['refresh_token'] === '' || $result['session_id'] === '') {
            throw new RuntimeException('Login respondió sin los datos completos de sesión.');
        }

        return $result;
    }

    public function countUnread(string $accessToken): int
    {
        [$response, $status] = $this->notifications
            ->CountUnread(new CountUnreadRequest, $this->authorization($accessToken), $this->callOptions)
            ->wait();

        $this->assertOk($status, 'notificaciones.v1.NotificationService/CountUnread');
        $this->assertResponseType($response, CountUnreadResponse::class, 'notificaciones.v1.NotificationService/CountUnread');

        return $response->getUnreadCount();
    }

    public function listUnread(string $accessToken, int $limit): array
    {
        $request = (new ListNotificationsRequest)
            ->setEstado('no_leido')
            ->setLimit(max(1, $limit));

        [$response, $status] = $this->notifications
            ->ListNotifications($request, $this->authorization($accessToken), $this->callOptions)
            ->wait();

        $this->assertOk($status, 'notificaciones.v1.NotificationService/ListNotifications');
        $this->assertResponseType($response, ListNotificationsResponse::class, 'notificaciones.v1.NotificationService/ListNotifications');

        return $this->mapNotifications($response->getNotifications());
    }

    public function recentNotifications(?string $accessToken, int $limit): array
    {
        $request = (new ListNotificationsRequest)->setLimit(max(1, $limit));

        [$response, $status] = $this->notifications
            ->RecentNotifications($request, $this->authorization($accessToken), $this->callOptions)
            ->wait();

        $this->assertOk($status, 'notificaciones.v1.NotificationService/RecentNotifications');
        $this->assertResponseType($response, ListNotificationsResponse::class, 'notificaciones.v1.NotificationService/RecentNotifications');

        return $this->mapNotifications($response->getNotifications());
    }

    public function logout(string $accessToken, string $refreshToken): array
    {
        $request = (new LogoutRequest)
            ->setToken($accessToken)
            ->setRefreshToken($refreshToken);

        [$response, $status] = $this->auth
            ->Logout($request, [], $this->callOptions)
            ->wait();

        $this->assertOk($status, 'auth.v1.AuthService/Logout');
        $this->assertResponseType($response, AuthGenericResponse::class, 'auth.v1.AuthService/Logout');

        return [
            'success' => $response->getSuccess(),
            'message' => $response->getMessage(),
        ];
    }

    public function validateToken(string $accessToken): bool
    {
        $request = (new ValidateTokenRequest)->setToken($accessToken);

        [$response, $status] = $this->auth
            ->ValidateToken($request, [], $this->callOptions)
            ->wait();

        $this->assertOk($status, 'auth.v1.AuthService/ValidateToken');
        $this->assertResponseType($response, ValidateTokenResponse::class, 'auth.v1.AuthService/ValidateToken');

        return $response->getIsValid();
    }

    /** @return array<string, list<string>> */
    private function authorization(?string $accessToken): array
    {
        return $accessToken === null
            ? []
            : ['authorization' => ['Bearer '.$accessToken]];
    }

    /**
     * @return list<array<string, bool|string|null>>
     */
    private function mapNotifications(mixed $notifications): array
    {
        if (! is_iterable($notifications)) {
            throw new RuntimeException('NotificationService devolvió una colección inesperada.');
        }

        $items = [];

        foreach ($notifications as $notification) {
            if (! $notification instanceof Notification) {
                throw new RuntimeException('NotificationService devolvió un elemento inesperado.');
            }

            $items[] = [
                'id' => $notification->getId(),
                'titulo' => $notification->getTitulo(),
                'mensaje' => $notification->getMensaje(),
                'tipo' => $notification->getTipo(),
                'estado' => $notification->getEstado(),
                'leida' => $notification->getLeida(),
                'creado_en' => $notification->getCreadoEn(),
            ];
        }

        return $items;
    }

    private function assertOk(\stdClass $status, string $operation): void
    {
        if ($status->code === \Grpc\STATUS_OK) {
            return;
        }

        throw new GatewayRpcException(
            $operation,
            (int) $status->code,
            (string) ($status->details ?? ''),
        );
    }

    /**
     * @template T of object
     *
     * @param  class-string<T>  $expected
     *
     * @phpstan-assert T $response
     */
    private function assertResponseType(mixed $response, string $expected, string $operation): void
    {
        if (! $response instanceof $expected) {
            throw new RuntimeException("{$operation} devolvió un tipo de respuesta inesperado.");
        }
    }
}
