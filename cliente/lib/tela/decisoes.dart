import 'package:flutter/material.dart';

import '../estado/sala.dart';
import '../nucleo/modelos.dart';
import 'chat.dart';
import 'comum.dart';

class TelaDecisoes extends StatelessWidget {
  const TelaDecisoes({super.key, required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sala.decisoes,
        builder: (context, _) {
          final aberta = sala.decisoes.aberta;
          return aberta == null ? _Lista(sala: sala) : _Detalhe(sala: sala, conteudo: aberta.conteudo);
        },
      );
}

class _Lista extends StatelessWidget {
  const _Lista({required this.sala});

  final Sala sala;

  @override
  Widget build(BuildContext context) {
    final estado = sala.decisoes;
    final cores = Theme.of(context).colorScheme;
    final lista = estado.filtradas;
    return Column(children: [
      Material(
        color: cores.surface,
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            ListTile(
              leading: const Avatar(cor: Color(Perfil.corDecisoes), inicial: 'D', tamanho: 32),
              title: const Text('Decisões'),
              subtitle: Text('registro e consulta', style: TextStyle(color: cores.onSurfaceVariant)),
              trailing: IconButton(
                tooltip: 'Recarregar',
                icon: const Icon(Icons.refresh),
                onPressed: estado.carregar,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: TextField(
                onChanged: estado.filtrar,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filtrar por título, tag ou projeto'),
              ),
            ),
          ]),
        ),
      ),
      const Divider(),
      Expanded(
        child: !estado.carregada
            ? const Center(child: CircularProgressIndicator())
            : lista.isEmpty
                ? Center(
                    child: Text(estado.lista.isEmpty ? 'Nenhuma decisão registrada ainda.' : 'Nada com esse filtro.',
                        style: TextStyle(color: cores.onSurfaceVariant)))
                : ListView.separated(
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
                    itemBuilder: (context, i) {
                      final d = lista[i];
                      return ListTile(
                        title: Text(d.titulo),
                        subtitle: Text(
                          [d.data, if (d.projeto.isNotEmpty) d.projeto, if (d.tags.isNotEmpty) d.tags.join(', ')].join(' · '),
                          style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
                        ),
                        trailing: _Status(d.status),
                        onTap: () => estado.abrir(d.id),
                      );
                    },
                  ),
      ),
    ]);
  }
}

class _Status extends StatelessWidget {
  const _Status(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    final cor = switch (status) {
      'aceita' => const Color(0xFF4FAE7C),
      'revogada' => const Color(0xFFE05A5A),
      _ => const Color(0xFFE0A458),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
      child: Text(status, style: TextStyle(color: cor, fontSize: 12)),
    );
  }
}

class _Detalhe extends StatelessWidget {
  const _Detalhe({required this.sala, required this.conteudo});

  final Sala sala;
  final String conteudo;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) sala.decisoes.fecharDetalhe();
        },
        child: Column(children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              bottom: false,
              child: Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: sala.decisoes.fecharDetalhe),
                const Text('Decisão'),
                const Spacer(),
                IconButton(
                  tooltip: 'Copiar',
                  icon: const Icon(Icons.copy),
                  onPressed: () => copiar(context, conteudo),
                ),
              ]),
            ),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: SelectionArea(child: TextoMarkdown(conteudo)),
                ),
              ),
            ),
          ),
        ]),
      );
}
