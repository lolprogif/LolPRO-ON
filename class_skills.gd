extends RefCounted
# Initial class design catalog; combat execution is separate.
const CLASSES = {
"Guerreiro":[["Corte devastador",5],["Espada giratória",8],["Investida",10],["Defesa de ferro",12],["Fúria",15],["Impacto sísmico",20]],
"Ninja":[["Ataque duplo",5],["Camuflagem",8],["Lâmina venenosa",10],["Flecha perfurante",12],["Passo fantasma",15],["Nuvem tóxica",20]]
}
static func skills_for(character_class: String) -> Array:
	return CLASSES.get(character_class,[]).duplicate(true)
